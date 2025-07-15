const { createClient } = require('@supabase/supabase-js');
const { AssemblyAI } = require('assemblyai');
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

exports.handler = withLogging('transcribe-status', async (event, context) => {
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

    // Parse and validate request body
    let requestBody;
    try {
      requestBody = JSON.parse(event.body || '{}');
    } catch (e) {
      logger.warn('Invalid JSON in request body', { userId: user.id });
      return createErrorResponse(new Error('Invalid JSON in request body'), 400);
    }
    
    const { id, userId } = requestBody;
    
    // Validate required fields
    if (!id || typeof id !== 'string') {
      logger.warn('Missing or invalid transcription ID', { userId: user.id, providedId: id });
      return createErrorResponse(new Error('Valid transcription ID is required'), 400);
    }
    
    // Sanitize the ID
    const sanitizedId = Validator.sanitizeText(id, {
      maxLength: 100,
      allowHtml: false,
      allowNewlines: false
    });

    // Verify user can access this transcription
    if (userId && userId !== user.id) {
      logger.security('unauthorized_transcription_access', {
        userId: user.id,
        requestedUserId: userId,
        transcriptionId: sanitizedId,
        ip: event.headers['x-forwarded-for']
      });
      return createErrorResponse(
        new Error('Access denied: You can only check your own transcriptions'), 
        403
      );
    }

    logger.info('Checking transcription status', {
      transcriptionId: sanitizedId,
      userId: user.id
    });
    
    const assembly = new AssemblyAI({
      apiKey: process.env.ASSEMBLYAI_API_KEY,
    });
    
    logger.apiCall('AssemblyAI', 'transcripts.get', {
      transcriptionId: sanitizedId,
      userId: user.id
    });

    // Fetch the transcript status from AssemblyAI with circuit breaker
    const getTranscriptWithTimeout = withTimeout(
      () => assemblyAIBreaker.execute(() => assembly.transcripts.get(sanitizedId)),
      30000 // 30 second timeout
    );
    
    const transcript = await getTranscriptWithTimeout();

    logger.info('Transcription status retrieved successfully', {
      transcriptionId: sanitizedId,
      userId: user.id,
      status: transcript.status,
      hasText: !!transcript.text,
      segmentCount: transcript.words?.length || 0
    });

    const responseData = {
      id: transcript.id,
      text: transcript.text,
      segments: transcript.words,
      status: transcript.status,
      userId: user.id,
      metadata: {
        audioUrl: transcript.audio_url,
        processingTime: transcript.processing_time,
        confidence: transcript.confidence,
        retrievedAt: new Date().toISOString()
      }
    };
    
    // Add rate limit headers if available
    const additionalHeaders = context.rateLimitHeaders || {};
    additionalHeaders.origin = event.headers.origin;
    
    return createSuccessResponse(responseData, 200, additionalHeaders);
  } catch (error) {
    logger.error('Transcription status check failed', {
      userId: event.user?.id,
      transcriptionId: event.body ? JSON.parse(event.body).id : 'unknown',
      errorType: error.constructor.name
    }, error);
    
    // Determine appropriate status code
    let statusCode = 500;
    if (error.message.includes('Circuit breaker')) {
      statusCode = 503; // Service Unavailable
    } else if (error.message.includes('timed out')) {
      statusCode = 408; // Request Timeout
    } else if (error.message.includes('not found') || error.message.includes('404')) {
      statusCode = 404; // Not Found
    } else if (error.message.includes('API key') || error.message.includes('quota')) {
      statusCode = 503; // Service Unavailable
    }
    
    return createErrorResponse(error, statusCode);
  }
});