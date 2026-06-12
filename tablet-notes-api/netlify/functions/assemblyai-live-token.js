const { createClient } = require('@supabase/supabase-js');
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
const { getSubscriptionState } = require('./utils/subscriptionTier');

// Circuit breaker for AssemblyAI API
const assemblyAIBreaker = new CircuitBreaker(3, 60000);

exports.handler = withLogging('assemblyai-live-token', async (event, context) => {
  const logger = event.logger;
  
  // Handle CORS preflight
  const corsResponse = handleCORS(event);
  if (corsResponse) return corsResponse;

  if (event.httpMethod !== 'POST') {
    return createErrorResponse(new Error('Method Not Allowed'), 405);
  }
  
  // Apply rate limiting
  const rateLimitMiddleware = createRateLimitMiddleware('general');
  const rateLimitResponse = await rateLimitMiddleware(event, context);
  if (rateLimitResponse) {
    logger.rateLimit(event.user?.id || 'anonymous', 'general', false);
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

    // Live transcription is paid-only. Tier comes from profiles (the same
    // source summarize uses) and defaults to free — previously this read
    // user_metadata and defaulted missing metadata to 'pro' (TAB-37).
    const supabaseUrl = process.env.SUPABASE_URL;
    const supabaseServiceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

    if (!supabaseUrl || !supabaseServiceKey) {
      logger.error('Missing Supabase configuration; cannot verify subscription tier');
      return createErrorResponse(new Error('Live transcription service not available'), 503);
    }

    const supabase = createClient(supabaseUrl, supabaseServiceKey);
    const subscription = await getSubscriptionState({ supabase, userId: user.id, logger });

    if (!subscription.isPaid) {
      logger.warn('Live transcription access denied', {
        userId: user.id,
        tier: subscription.tier
      });
      return createErrorResponse(
        new Error('Live transcription requires an active Pro or Premium subscription'),
        403
      );
    }

    // Get the AssemblyAI API key from environment variables
    const assemblyaiApiKey = process.env.ASSEMBLYAI_API_KEY;
    if (!assemblyaiApiKey) {
      logger.error('AssemblyAI API key not configured');
      return createErrorResponse(new Error('Live transcription service not available'), 503);
    }

    logger.info('Generating AssemblyAI session token', { userId: user.id });
    logger.apiCall('AssemblyAI', 'realtime/token', { userId: user.id });
    
    // Generate temporary session token from AssemblyAI with circuit breaker
    // expires_in_seconds: Token validity (max 600 seconds based on API validation)
    // max_session_duration_seconds: How long the streaming session can last (max 10800 = 3 hours)
    const tokenRequestWithTimeout = withTimeout(
      () => assemblyAIBreaker.execute(() => fetch(`https://streaming.assemblyai.com/v3/token?expires_in_seconds=600&max_session_duration_seconds=10800`, {
        method: 'GET',
        headers: {
          'Authorization': assemblyaiApiKey,
          'User-Agent': 'TabletNotes/1.0'
        }
      })),
      10000 // 10 second timeout
    );
    
    const response = await tokenRequestWithTimeout();

    if (!response.ok) {
      const errorText = await response.text();
      logger.error('AssemblyAI token generation failed', {
        userId: user.id,
        status: response.status,
        statusText: response.statusText,
        errorText: errorText.substring(0, 200)
      });
      throw new Error(`AssemblyAI API error: ${response.status}`);
    }

    const tokenData = await response.json();

    logger.info('Session token generated successfully', {
      userId: user.id,
      expiresIn: tokenData.expires_in_seconds
    });

    const responseData = {
      sessionToken: tokenData.token,
      expiresIn: tokenData.expires_in_seconds,
      userId: user.id,
      metadata: {
        generatedAt: new Date().toISOString(),
        service: 'AssemblyAI',
        type: 'realtime'
      }
    };
    
    // Add rate limit headers if available
    const additionalHeaders = context.rateLimitHeaders || {};
    additionalHeaders.origin = event.headers.origin;
    
    const successResponse = createSuccessResponse(responseData, 200, additionalHeaders);

    // Backward compatibility: older iOS clients decode sessionToken at the top level.
    // Keep the standardized wrapper while mirroring legacy fields.
    try {
      const wrappedBody = JSON.parse(successResponse.body);
      successResponse.body = JSON.stringify({
        ...wrappedBody,
        sessionToken: responseData.sessionToken,
        expiresIn: responseData.expiresIn,
        userId: responseData.userId,
        metadata: responseData.metadata
      });
    } catch (responseTransformError) {
      logger.warn('Failed to append legacy token fields to response body', {
        userId: user.id,
        error: responseTransformError.message
      });
    }

    return successResponse;

  } catch (error) {
    logger.error('Live token generation failed', {
      userId: event.user?.id,
      errorType: error.constructor.name
    }, error);
    
    // Determine appropriate status code
    let statusCode = 500;
    if (error.message.includes('Circuit breaker')) {
      statusCode = 503; // Service Unavailable
    } else if (error.message.includes('timed out')) {
      statusCode = 408; // Request Timeout
    } else if (error.message.includes('API key') || error.message.includes('quota')) {
      statusCode = 503; // Service Unavailable
    }
    
    return createErrorResponse(error, statusCode);
  }
});
