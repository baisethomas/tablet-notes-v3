const { createClient } = require('@supabase/supabase-js');
const { buildAudioObjectPath } = require('./utils/storagePath');
const { createRateLimitMiddleware } = require('./utils/rateLimiter');
const { Validator, LIMITS, ALLOWED_AUDIO_TYPES } = require('./utils/validator');
const { 
  handleCORS, 
  createAuthMiddleware, 
  withTimeout,
  CircuitBreaker,
  createErrorResponse,
  createSuccessResponse
} = require('./utils/security');
const { withLogging } = require('./utils/logger');

// Circuit breaker for Supabase Storage
const supabaseStorageBreaker = new CircuitBreaker(3, 60000);

exports.handler = withLogging('generate-upload-url', async (event, context) => {
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
  const rateLimitMiddleware = createRateLimitMiddleware('upload');
  const rateLimitResponse = await rateLimitMiddleware(event, context);
  if (rateLimitResponse) {
    logger.rateLimit(event.user?.id || 'anonymous', 'upload', false, {
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
    const validationMiddleware = Validator.createValidationMiddleware('fileUpload', 'body');
    const validationResponse = validationMiddleware(event);
    if (validationResponse) {
      logger.validationError(validationResponse.body ? JSON.parse(validationResponse.body).details : [], {
        userId: user.id
      });
      return validationResponse;
    }
    
    const { fileName, contentType, fileSize } = event.validatedData;
    
    // Additional file validation
    const fileValidation = Validator.validateFileUpload(fileName, contentType, fileSize);
    if (!fileValidation.valid) {
      logger.warn('File validation failed', {
        userId: user.id,
        fileName,
        contentType,
        fileSize,
        errors: fileValidation.errors
      });
      return createErrorResponse(new Error(`File validation failed: ${fileValidation.errors.map(e => e.message).join(', ')}`), 400);
    }

    // Use service role key to bypass RLS for creating signed upload URLs
    const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY);

    // A path derived from the sermon id is stable across retries, so an
    // interrupted upload replaces its own partial object instead of orphaning
    // it (TAB-73). Clients that predate `sermonLocalId` keep the random path.
    const { path: filePath, stable: isStablePath } = buildAudioObjectPath({
      userId: user.id,
      sermonLocalId: event.validatedData.sermonLocalId,
      fileName
    });
    
    logger.info('Generating signed upload URL', { 
      userId: user.id,
      fileName,
      contentType,
      fileSize,
      filePath
    });
    
    // Create signed URL with circuit breaker and timeout
    const createSignedUrlWithTimeout = withTimeout(
      () => supabaseStorageBreaker.execute(() =>
        supabase.storage
          .from('sermon-audio')
          .createSignedUploadUrl(filePath, {
            // Overwriting is only safe on a stable, sermon-derived path, where
            // the existing object can only be this sermon's earlier attempt.
            // A random path must never upsert.
            upsert: isStablePath
          })
      ),
      30000 // 30 second timeout
    );

    const { data, error } = await createSignedUrlWithTimeout();

    if (error) {
      logger.error('Failed to create signed upload URL', {
        userId: user.id,
        filePath,
        bucketName: 'sermon-audio'
      }, error);
      throw error;
    }

    logger.info('Signed upload URL created successfully', {
      userId: user.id,
      filePath,
      urlPath: data.path
    });

    const responseData = {
      uploadUrl: data.signedUrl,
      path: data.path,
      token: data.token,
      userId: user.id,
      metadata: {
        originalFileName: fileName,
        contentType,
        fileSize,
        maxFileSize: LIMITS.AUDIO_FILE_SIZE,
        allowedTypes: ALLOWED_AUDIO_TYPES
      }
    };
    
    // Add rate limit headers if available
    const additionalHeaders = context.rateLimitHeaders || {};
    additionalHeaders.origin = event.headers.origin;
    
    return createSuccessResponse(responseData, 200, additionalHeaders);
  } catch (error) {
    logger.error('Upload URL generation failed', {
      userId: event.user?.id,
      fileName: event.validatedData?.fileName,
      errorType: error.constructor.name
    }, error);
    
    // Determine appropriate status code
    let statusCode = 500;
    if (error.message.includes('Circuit breaker')) {
      statusCode = 503; // Service Unavailable
    } else if (error.message.includes('timed out')) {
      statusCode = 408; // Request Timeout
    } else if (error.message.includes('quota') || error.message.includes('storage limit')) {
      statusCode = 507; // Insufficient Storage
    }
    
    return createErrorResponse(error, statusCode);
  }
});