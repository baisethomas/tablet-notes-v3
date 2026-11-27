const { createClient } = require('@supabase/supabase-js');
const OpenAI = require('openai');
const { createRateLimitMiddleware } = require('./utils/rateLimiter');
const { Validator, LIMITS } = require('./utils/validator');
const { 
  handleCORS, 
  createAuthMiddleware, 
  withTimeout,
  CircuitBreaker,
  createErrorResponse,
  createSuccessResponse
} = require('./utils/security');
const { withLogging } = require('./utils/logger');
const { getSubscriptionState } = require('./utils/subscriptionTier');
const { secretMatches } = require('./utils/processingJobs');
const {
  missingRequiredHeadings,
  completeWithHeadingRetry,
  buildRetryUserMessage
} = require('./utils/summaryFormat');
const { buildSummarizeSystemPrompt } = require('./utils/summarizePrompt');

// Circuit breaker for OpenAI API
const openAIBreaker = new CircuitBreaker(5, 30000); // 5 failures, 30 second timeout

exports.handler = withLogging('summarize', async (event, context) => {
  const logger = event.logger;
  
  // Handle CORS preflight
  const corsResponse = handleCORS(event);
  if (corsResponse) return corsResponse;
  
  // Validate request size
  const sizeValidation = Validator.validateRequestSize(event);
  if (!sizeValidation.valid) {
    logger.warn('Request size validation failed', { error: sizeValidation.error });
    return createErrorResponse(new Error(sizeValidation.error), 413);
  }

  if (event.httpMethod !== 'POST') {
    return createErrorResponse(new Error('Method Not Allowed'), 405);
  }
  
  // Internal service path (TAB-72): the jobs reaper generates summaries for
  // durable summary jobs, on behalf of a user who is not present to sign the
  // request. It authenticates with the same shared secret the AssemblyAI
  // webhook uses and names the user it is acting for.
  //
  // This exists so there is exactly ONE copy of the summarization prompt and
  // OpenAI call. The alternative — a second internal endpoint, or duplicating
  // ~230 lines of prompt into the reaper — is precisely the kind of divergence
  // that produced the two drifting completion paths this PR is already fixing.
  //
  // It is NOT a general auth bypass: the secret is server-held (never shipped
  // to clients), and the acting user id comes from the job row the reaper read
  // out of Postgres, not from anything a client supplied.
  const internalSecret = process.env.ASSEMBLYAI_WEBHOOK_SECRET;
  const providedInternalSecret = event.headers['x-tabletnotes-internal-secret'];
  let isInternalCall = false;

  if (providedInternalSecret) {
    if (!internalSecret || !secretMatches(providedInternalSecret, internalSecret)) {
      logger.security('internal_summarize_auth_failed', { ip: event.headers['x-forwarded-for'] });
      return createErrorResponse(new Error('Unauthorized'), 401);
    }
    let internalBody;
    try {
      internalBody = JSON.parse(event.body || '{}');
    } catch (_) {
      return createErrorResponse(new Error('Invalid JSON in request body'), 400);
    }
    if (!Validator.isValidUserId(internalBody.userId)) {
      return createErrorResponse(new Error('Internal call requires a valid userId'), 400);
    }
    event.user = { id: internalBody.userId };
    isInternalCall = true;
    logger.info('Authenticated internal summarize call', { userId: internalBody.userId });
  }

  if (!isInternalCall) {
    // Apply rate limiting (skipped for internal calls: the reaper is already
    // rate-limited by its own 5-minute schedule and per-sweep batch cap, and a
    // user-keyed limit would make the queue starve itself).
    const rateLimitMiddleware = createRateLimitMiddleware('summarization');
    const rateLimitResponse = await rateLimitMiddleware(event, context);
    if (rateLimitResponse) {
      logger.rateLimit(event.user?.id || 'anonymous', 'summarization', false, {
        statusCode: rateLimitResponse.statusCode
      });
      return rateLimitResponse;
    }

    // Apply authentication
    const authMiddleware = createAuthMiddleware();
    const authResponse = await authMiddleware(event);
    if (authResponse) {
      logger.security('authentication_failed', {
        reason: 'missing_or_invalid_token',
        ip: event.headers['x-forwarded-for']
      });
      return authResponse;
    }
  }

  try {
    const user = event.user; // User was authenticated by middleware
    logger.info('User authenticated successfully', { userId: user.id });
    
    // Validate request body
    const validationMiddleware = Validator.createValidationMiddleware('summarization', 'body');
    const validationResponse = validationMiddleware(event);
    if (validationResponse) {
      logger.validationError(validationResponse.body ? JSON.parse(validationResponse.body).details : [], {
        userId: user.id
      });
      return validationResponse;
    }
    
    const { text, type = 'sermon', serviceType, length = 'medium', includeScripture = true, tone = 'conversational' } = event.validatedData;
    
    // Use serviceType if provided, otherwise fall back to type
    const actualServiceType = serviceType || type;
    
    // Debug logging for received text
    logger.info('Received text for summarization', {
      userId: user.id,
      textLength: text ? text.length : 0,
      textPreview: text ? text.substring(0, 200) + '...' : 'null',
      textSuffix: text && text.length > 200 ? '...' + text.substring(text.length - 100) : '',
      type,
      serviceType,
      actualServiceType,
      length,
      includeScripture,
      tone
    });
    
    // Sanitize input text for the LLM sink: length bound + control-character
    // strip only. sanitizeText's HTML escaping corrupted every apostrophe in
    // the transcript and inflated token cost (TAB-68).
    const sanitizedText = Validator.sanitizeLLMText(text, {
      maxLength: LIMITS.SUMMARY_TEXT_LENGTH
    });
    
    // Debug logging after sanitization
    logger.info('Text after sanitization', {
      userId: user.id,
      originalLength: text ? text.length : 0,
      sanitizedLength: sanitizedText.length,
      sanitizedPreview: sanitizedText.substring(0, 200) + '...',
      sanitizedSuffix: sanitizedText.length > 200 ? '...' + sanitizedText.substring(sanitizedText.length - 100) : ''
    });
    
    if (sanitizedText.length < 50) {
      logger.warn('Text too short after sanitization', {
        userId: user.id,
        originalLength: text ? text.length : 0,
        sanitizedLength: sanitizedText.length
      });
      return createErrorResponse(new Error('Text is too short for meaningful summarization'), 400);
    }
    
    logger.info('Processing summarization request', { 
      userId: user.id,
      textLength: sanitizedText.length,
      type: actualServiceType,
      length,
      includeScripture,
      tone
    });

    const openai = new OpenAI({
      apiKey: process.env.OPENAI_API_KEY,
    });

    logger.apiCall('OpenAI', 'chat.completions.create', {
      model: 'gpt-4o-mini',
      textLength: sanitizedText.length,
      type: actualServiceType,
      userId: user.id
    });

    // Initialize Supabase client to fetch user profile
    const supabaseUrl = process.env.SUPABASE_URL;
    const supabaseServiceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
    
    if (!supabaseUrl || !supabaseServiceKey) {
      logger.error('Missing Supabase configuration', { userId: user.id });
      return createErrorResponse(new Error('Server configuration error'), 500);
    }
    
    const supabase = createClient(supabaseUrl, supabaseServiceKey);
    
    // Resolve subscription via the shared helper (single source of truth for
    // server-side tier checks). Paid + active + unexpired → premium summary.
    const subscription = await getSubscriptionState({ supabase, userId: user.id, logger });
    const userTier = subscription.isPaid ? 'premium' : 'basic';

    logger.info('Processing summary request', {
      userId: user.id,
      detectedTier: userTier,
      profileTier: subscription.tier,
      serviceType: actualServiceType,
      transcriptLength: text.length
    });

    // Create completion with circuit breaker and timeout.
    // TAB-120: if the first response is missing required headings, retry once
    // inside the same 55s budget. The public response shape is unchanged.
    const summarizeMessages = [
          {
            role: "system",
            content: buildSummarizeSystemPrompt({ userTier, serviceType: actualServiceType })
          },
          {
            role: "user",
            content: `Please summarize this ${actualServiceType} text: ${sanitizedText}`
          }
    ];

    const maxTokens = length === 'short' ? 1000 : length === 'long' ? 3000 : 2000;
    const temperature = tone === 'formal' ? 0.3 : tone === 'academic' ? 0.2 : 0.7;

    const createCompletion = (messages) => openAIBreaker.execute(() =>
      openai.chat.completions.create({
        model: 'gpt-4o-mini',
        messages,
        max_tokens: maxTokens,
        temperature
      })
    );

    // Netlify's synchronous execution limit is 60s (not configurable).
    // The previous 120s budget could never be honored. Abort just under
    // the platform ceiling so the client gets a clean, retryable 408
    // instead of an opaque 502. First attempt and one heading retry share
    // this budget.
    const completionWithTimeout = withTimeout(
      async () => {
        let firstContent = '';
        let lastCompletion = null;
        const result = await completeWithHeadingRetry({
          generate: async (attempt) => {
            const messages = attempt === 1
              ? summarizeMessages
              : [
                  ...summarizeMessages,
                  { role: 'assistant', content: firstContent },
                  { role: 'user', content: buildRetryUserMessage(missingRequiredHeadings(firstContent)) }
                ];
            lastCompletion = await createCompletion(messages);
            const content = lastCompletion.choices[0].message.content;
            if (attempt === 1) firstContent = content;
            return content;
          }
        });
        if (result.retried) {
          logger.info('Summary missing required headings; retried once', {
            userId: user.id,
            missing: result.missing,
            secondMissing: missingRequiredHeadings(result.content)
          });
        }
        return { ...result, completion: lastCompletion };
      },
      55000
    );

    const headingResult = await completionWithTimeout();
    const completion = headingResult.completion;
    const fullContent = headingResult.content;

    // Extract title from the response
    let title = null;
    let summary = fullContent;

    // Robust title extraction that handles multiple formats:
    // - "TITLE: Title Text"
    // - "**TITLE: Title Text**"
    // - "**TITLE: Title Text**\n\n"
    // - "TITLE: Title with **bold** text"
    // - "**TITLE: Title with **bold** text**"
    
    // First, try to match the entire title line (more reliable than trying to match markdown)
    // Match: optional opening **, "TITLE:", whitespace, then everything until end of line or closing ** + newline
    const titleLineMatch = fullContent.match(/^(\*\*)?TITLE:\s*(.+?)(?:\n|$)/);
    
    if (titleLineMatch) {
      // Extract the title text (everything after "TITLE: ")
      let extractedTitle = titleLineMatch[2].trim();
      
      // Remove closing markdown formatting if present (handle cases like "Title**" or "**Title**")
      // This handles titles that might have markdown in them or at the end
      extractedTitle = extractedTitle.replace(/\*\*$/, '').trim();
      
      // Remove opening markdown if it somehow got included (defensive)
      extractedTitle = extractedTitle.replace(/^\*\*/, '').trim();
      
      // Clean up any remaining markdown formatting at the edges
      extractedTitle = extractedTitle.replace(/^\*\*|\*\*$/g, '').trim();
      
      title = extractedTitle;
      
      // Remove the entire title line (including opening ** if present) from the summary
      const titleLineLength = titleLineMatch[0].length;
      summary = fullContent.substring(titleLineLength).trim();
      
      // Also remove any leading markdown that might be left (defensive cleanup)
      summary = summary.replace(/^\*\*/, '').trim();
      
      logger.info('Title extracted from TITLE: prefix', {
        userId: user.id,
        extractedTitle: title,
        titleLength: title.length,
        summaryStart: summary.substring(0, 50)
      });
    } else {
      // Fallback: try to find title in first line or first sentence
      // This handles cases where OpenAI doesn't follow the TITLE: format
      const firstLine = fullContent.split('\n')[0].trim();
      const firstSentence = fullContent.split(/[.!?]\s/)[0].trim();
      
      // Use first line if it's reasonable length, otherwise first sentence
      let fallbackTitle = firstLine.length <= 80 && firstLine.length > 0 
        ? firstLine 
        : (firstSentence.length > 0 ? firstSentence.substring(0, 80) : 'Sermon Summary');
      
      // Clean markdown formatting from fallback title
      fallbackTitle = fallbackTitle.replace(/^\*\*|\*\*$/g, '').trim();
      
      // Remove "TITLE:" prefix if present (case-insensitive)
      fallbackTitle = fallbackTitle.replace(/^(\*\*)?TITLE:\s*/i, '').trim();
      fallbackTitle = fallbackTitle.replace(/^\*\*|\*\*$/g, '').trim();
      
      title = fallbackTitle || 'Sermon Summary';
      
      logger.info('Title extracted from fallback method', {
        userId: user.id,
        fallbackTitle: title,
        firstLine: firstLine.substring(0, 50),
        usedFirstLine: firstLine.length <= 80
      });
    }
    
    // Final validation: ensure title is not empty
    if (!title || title.trim().length === 0) {
      title = 'Sermon Summary';
      logger.warn('Title was empty after extraction, using default', {
        userId: user.id,
        fullContentPreview: fullContent.substring(0, 200)
      });
    }

    logger.info('Summarization completed successfully', {
      userId: user.id,
      title: title,
      summaryLength: summary.length,
      tokensUsed: completion.usage?.total_tokens,
      model: 'gpt-4o-mini'
    });

    const responseData = {
      title,
      summary,
      usage: completion.usage,
      userId: user.id,
      metadata: {
        type: actualServiceType,
        length,
        includeScripture,
        tone,
        originalTextLength: sanitizedText.length,
        summaryLength: summary.length,
        titleLength: title?.length || 0
      }
    };
    
    // Add rate limit headers if available
    const additionalHeaders = context.rateLimitHeaders || {};
    additionalHeaders.origin = event.headers.origin;
    
    return createSuccessResponse(responseData, 200, additionalHeaders);

  } catch (error) {
    // Detailed error logging for OpenAI API failures
    const errorDetails = {
      userId: event.user?.id,
      textLength: event.validatedData?.text?.length,
      errorType: error.constructor.name,
      errorMessage: error.message,
      errorStack: error.stack,
      circuitBreakerState: openAIBreaker.state,
      circuitBreakerFailureCount: openAIBreaker.failureCount
    };

    // Extract OpenAI-specific error information
    if (error.response) {
      errorDetails.openAIStatus = error.response.status;
      errorDetails.openAIStatusText = error.response.statusText;
      errorDetails.openAIError = error.response.data;
      errorDetails.openAIHeaders = error.response.headers;
    }

    // Check for specific OpenAI error types
    if (error.code) {
      errorDetails.openAICode = error.code;
    }

    if (error.type) {
      errorDetails.openAIType = error.type;
    }

    // Log detailed error information
    logger.error('Summarization request failed', errorDetails, error);
    
    // Determine appropriate status code based on error type
    let statusCode = 500;
    let errorMessage = error.message || 'An unexpected error occurred';
    
    // Check for OpenAI RateLimitError first (OpenAI SDK throws custom error classes)
    if (error.constructor.name === 'RateLimitError' || error.code === 'rate_limit_exceeded' || 
        (error.message && error.message.includes('429') && error.message.includes('Rate limit'))) {
      statusCode = 429; // Too Many Requests
      
      // Extract retry time from error message (format: "Please try again in X.XXXs")
      const retryMatch = error.message.match(/Please try again in ([\d.]+)s/i);
      const retrySeconds = retryMatch ? parseFloat(retryMatch[1]) : null;
      
      if (retrySeconds) {
        errorMessage = `Rate limit exceeded. Please try again in ${Math.ceil(retrySeconds)} seconds.`;
        errorDetails.retryAfter = retrySeconds;
      } else {
        errorMessage = 'Rate limit exceeded. Please try again in a moment.';
      }
      
      logger.warn('OpenAI rate limit exceeded', {
        userId: event.user?.id,
        retryAfter: retrySeconds,
        errorType: error.type,
        errorCode: error.code
      });
    } else if (error.message && error.message.includes('Circuit breaker')) {
      statusCode = 503; // Service Unavailable
      errorMessage = 'The summarization service is temporarily unavailable. Please try again in a moment.';
      
      // Log circuit breaker state for debugging
      logger.warn('Circuit breaker is OPEN', {
        userId: event.user?.id,
        state: openAIBreaker.state,
        failureCount: openAIBreaker.failureCount,
        nextAttempt: openAIBreaker.nextAttempt,
        timeUntilRetry: openAIBreaker.nextAttempt ? Math.max(0, openAIBreaker.nextAttempt - Date.now()) : 0
      });
    } else if (error.message && error.message.includes('timed out')) {
      statusCode = 408; // Request Timeout
      errorMessage = 'The summarization request timed out. Please try again with a shorter transcript.';
    } else if (error.response) {
      // Handle OpenAI API HTTP response errors
      const status = error.response.status;
      
      if (status === 429) {
        // Rate limit error from HTTP response
        statusCode = 429;
        errorMessage = 'Rate limit exceeded. Please try again in a moment.';
        
        // Extract retry-after header if available
        const retryAfter = error.response.headers?.['retry-after'] || error.response.headers?.['Retry-After'];
        if (retryAfter) {
          errorDetails.retryAfter = retryAfter;
        }
      } else if (status === 401) {
        // Authentication error
        statusCode = 500;
        errorMessage = 'OpenAI API authentication failed. Please contact support.';
      } else if (status === 402 || status === 403) {
        // Payment/quota error
        statusCode = 503;
        errorMessage = 'OpenAI API quota exceeded. Please contact support.';
      } else if (status >= 500 && status < 600) {
        // OpenAI server error
        statusCode = 503;
        errorMessage = 'OpenAI service is temporarily unavailable. Please try again later.';
      } else {
        statusCode = status;
        errorMessage = error.response.data?.error?.message || error.message || 'OpenAI API error occurred';
      }
    } else if (error.message && (error.message.includes('quota') || error.message.toLowerCase().includes('rate limit'))) {
      // Fallback for rate limit detection
      statusCode = 429; // Too Many Requests
      errorMessage = 'Rate limit exceeded. Please try again in a moment.';
    } else if (error.code === 'ENOTFOUND' || error.code === 'ECONNREFUSED' || error.code === 'ETIMEDOUT') {
      // Network errors
      statusCode = 503;
      errorMessage = 'Network error connecting to OpenAI. Please check your connection and try again.';
    }
    
    return createErrorResponse(new Error(errorMessage), statusCode);
  }
});
