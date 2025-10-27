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

// Circuit breaker for AssemblyAI API
const assemblyAIBreaker = new CircuitBreaker(3, 60000);

// Helper function to check if user has pro/premium subscription
function hasLiveTranscriptionAccess(user) {
  // Check if user has pro or premium tier (default to pro for new users)
  const tier = user.user_metadata?.subscription_tier || 'pro';
  return tier === 'pro' || tier === 'premium';
}

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

    // Check if user has access to live transcription
    if (!hasLiveTranscriptionAccess(user)) {
      logger.warn('Live transcription access denied', {
        userId: user.id,
        tier: user.user_metadata?.subscription_tier || 'unknown'
      });
      return createErrorResponse(
        new Error('Live transcription requires Pro or Premium subscription'), 
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
    // Note: v3 API max is 600 seconds (10 minutes)
    const tokenRequestWithTimeout = withTimeout(
      () => assemblyAIBreaker.execute(() => fetch(`https://streaming.assemblyai.com/v3/token?expires_in_seconds=600`, {
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
    
    return createSuccessResponse(responseData, 200, additionalHeaders);

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