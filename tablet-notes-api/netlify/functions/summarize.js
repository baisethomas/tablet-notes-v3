const { createClient } = require('@supabase/supabase-js');
const OpenAI = require('openai');
const { createRateLimitMiddleware } = require('./utils/rateLimiter');
const { Validator } = require('./utils/validator');
const { 
  handleCORS, 
  createAuthMiddleware, 
  withTimeout,
  CircuitBreaker,
  createErrorResponse,
  createSuccessResponse
} = require('./utils/security');
const { withLogging } = require('./utils/logger');

// Circuit breaker for OpenAI API
const openAIBreaker = new CircuitBreaker(3, 60000); // 3 failures, 1 minute timeout

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
  
  // Apply rate limiting
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
    
    const { text, type = 'sermon', length = 'medium', includeScripture = true, tone = 'conversational' } = event.validatedData;
    
    // Sanitize input text
    const sanitizedText = Validator.sanitizeText(text, {
      maxLength: 50000,
      allowHtml: false,
      allowNewlines: true
    });
    
    if (sanitizedText.length < 50) {
      return createErrorResponse(new Error('Text is too short for meaningful summarization'), 400);
    }
    
    logger.info('Processing summarization request', { 
      userId: user.id,
      textLength: sanitizedText.length,
      type,
      length,
      includeScripture,
      tone
    });

    const openai = new OpenAI({
      apiKey: process.env.OPENAI_API_KEY,
    });

    logger.apiCall('OpenAI', 'chat.completions.create', {
      model: 'gpt-3.5-turbo',
      textLength: sanitizedText.length,
      type,
      userId: user.id
    });

    // Log the detected subscription tier for debugging
    const userTier = user.user_metadata?.subscription_tier || 'basic';
    logger.info('Processing summary request', {
      userId: user.id,
      detectedTier: userTier,
      serviceType: type,
      transcriptLength: text.length
    });

    // Create completion with circuit breaker and timeout
    const completionWithTimeout = withTimeout(
      () => openAIBreaker.execute(() => openai.chat.completions.create({
        model: "gpt-3.5-turbo",
        messages: [
          {
            role: "system",
            content: `You are an advanced theological assistant that creates intelligent summaries tailored to user subscription tiers and service types. Maintain deep respect for biblical accuracy and spiritual formation while adapting output complexity based on user tier and context.

**User Tier: ${user.user_metadata?.subscription_tier || 'basic'}**
**Service Type: ${type}**

**Core Principles:**
- Maintain absolute faithfulness to the original content - never add interpretations not present
- Preserve the speaker's theological perspective and denominational context
- Use precise biblical language and avoid casual or trendy expressions
- Emphasize scriptural authority and careful exegesis
- Adapt depth and structure based on user tier and service type

**BASIC TIER OUTPUT:**
For Basic tier users, provide a concise, accessible summary:

**Brief Summary** (2-3 sentences)
Capture the main message and primary biblical text(s). Focus on the central point communicated.

**Key Points** (3-4 main points)
- Main arguments and supporting evidence
- Specific biblical references as used by speaker
- Core theological concepts presented
- Primary applications given by speaker

**Scripture References**
- List all Bible passages mentioned with standard references
- Note primary texts vs. supporting passages

**Application**
- Practical applications explicitly given by speaker
- Specific calls to action or responses requested

**PREMIUM TIER OUTPUT:**
For Premium tier users, provide comprehensive analysis with enhanced features:

**Executive Summary** (2-3 sentences)
Capture the sermon's central thesis, primary biblical text(s), and theological significance within broader biblical narrative.

**Detailed Analysis**
**Main Arguments** (4-6 substantial points)
- Extract speaker's theological framework and supporting evidence
- Include specific biblical references with contextual significance
- Preserve theological terminology and doctrinal language
- Note historical, cultural, and linguistic context provided
- Cross-reference related biblical themes and passages

**Exegetical Insights**
- Original language observations and textual analysis
- Historical background and cultural context
- Hermeneutical approach and interpretive methodology
- Connection to broader biblical theology

**Scripture Deep Dive**
- Comprehensive list of all biblical references with context
- Primary texts with detailed exposition
- Supporting passages and their relevance
- Cross-references to related biblical themes
- Translation notes and textual considerations

**Practical Applications**
- Immediate applications for Christian living
- Long-term spiritual formation implications
- Community and church application
- Personal discipleship pathways

**Study Questions**
- Reflection questions for personal meditation
- Discussion prompts for small groups
- Application challenges for spiritual growth
- Further study recommendations

**Sermon Structure Analysis**
- Homiletical structure and flow
- Transition techniques and rhetorical devices
- Audience engagement strategies
- Theological progression and development

**Related Insights**
- Connections to systematic theology
- Historical church teaching and tradition
- Contemporary relevance and application
- Recommended resources for deeper study

**SERVICE TYPE ADAPTATIONS:**

**Sunday Morning Sermon:**
- Focus on congregational edification and worship application
- Emphasize community implications and corporate discipleship
- Include family and household applications

**Bible Study:**
- Emphasize exegetical accuracy and study methodology
- Include detailed cross-references and study resources
- Focus on personal growth and discipleship development

**Youth Groups:**
- Highlight practical applications for young people
- Include relevant cultural connections and modern examples
- Emphasize community and peer relationships

**Conference/Special Event:**
- Focus on broader theological themes and implications
- Include ministry and leadership applications
- Emphasize transformational and motivational elements

**Guidelines:**
- Never speculate beyond what the speaker actually said
- Preserve denominational distinctives and theological terminology
- Maintain reverence for Scripture as the final authority
- Focus on spiritual edification and practical transformation
- Adapt complexity and depth based on user tier
- Ensure all content serves spiritual growth and biblical understanding`
          },
          {
            role: "user",
            content: `Please summarize this ${type} text: ${sanitizedText}`
          }
        ],
        max_tokens: length === 'short' ? 500 : length === 'long' ? 1500 : 1000,
        temperature: tone === 'formal' ? 0.3 : tone === 'academic' ? 0.2 : 0.7
      })),
      120000 // 2 minute timeout
    );
    
    const completion = await completionWithTimeout();

    const summary = completion.choices[0].message.content;
    
    logger.info('Summarization completed successfully', {
      userId: user.id,
      summaryLength: summary.length,
      tokensUsed: completion.usage?.total_tokens,
      model: 'gpt-3.5-turbo'
    });
    
    const responseData = {
      summary,
      usage: completion.usage,
      userId: user.id,
      metadata: {
        type,
        length,
        includeScripture,
        tone,
        originalTextLength: sanitizedText.length,
        summaryLength: summary.length
      }
    };
    
    // Add rate limit headers if available
    const additionalHeaders = context.rateLimitHeaders || {};
    additionalHeaders.origin = event.headers.origin;
    
    return createSuccessResponse(responseData, 200, additionalHeaders);

  } catch (error) {
    logger.error('Summarization request failed', {
      userId: event.user?.id,
      textLength: event.validatedData?.text?.length,
      errorType: error.constructor.name
    }, error);
    
    // Determine appropriate status code
    let statusCode = 500;
    if (error.message.includes('Circuit breaker')) {
      statusCode = 503; // Service Unavailable
    } else if (error.message.includes('timed out')) {
      statusCode = 408; // Request Timeout
    } else if (error.message.includes('quota') || error.message.includes('rate limit')) {
      statusCode = 429; // Too Many Requests
    }
    
    return createErrorResponse(error, statusCode);
  }
});