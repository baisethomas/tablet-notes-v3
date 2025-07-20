const { createClient } = require('@supabase/supabase-js');
const { AssemblyAI } = require('assemblyai');
const { createRateLimitMiddleware } = require('./utils/rateLimiter');
const { Validator } = require('./utils/validator');
const { 
  handleCORS, 
  createAuthMiddleware, 
  checkResourceOwnership, 
  withTimeout,
  CircuitBreaker,
  createErrorResponse,
  createSuccessResponse
} = require('./utils/security');
const { withLogging } = require('./utils/logger');

// Circuit breaker for AssemblyAI API
const assemblyAIBreaker = new CircuitBreaker(3, 60000); // 3 failures, 1 minute timeout

exports.handler = withLogging('transcribe', async (event, context) => {
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
    const rateLimitMiddleware = createRateLimitMiddleware('transcription');
    const rateLimitResponse = await rateLimitMiddleware(event, context);
    if (rateLimitResponse) {
        logger.rateLimit(event.user?.id || 'anonymous', 'transcription', false, {
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
        const supabaseUrl = process.env.SUPABASE_URL;
        const supabaseKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
        
        if (!supabaseUrl || !supabaseKey) {
            logger.error('Supabase configuration missing', { 
                hasUrl: !!supabaseUrl,
                hasKey: !!supabaseKey 
            });
            return createErrorResponse(new Error('Server configuration error'), 500);
        }

        const supabase = createClient(supabaseUrl, supabaseKey);
        const user = event.user; // User was authenticated by middleware
        
        logger.info('User authenticated successfully', { userId: user.id });
        
        // Validate request body
        const validationMiddleware = Validator.createValidationMiddleware('transcription', 'body');
        const validationResponse = validationMiddleware(event);
        if (validationResponse) {
            logger.validationError(validationResponse.body ? JSON.parse(validationResponse.body).details : [], {
                userId: user.id
            });
            return validationResponse;
        }
        
        const { filePath } = event.validatedData;
        logger.info('Processing transcription request', { filePath, userId: user.id });

        // Verify user owns the file
        if (!checkResourceOwnership(user, filePath)) {
            logger.security('unauthorized_file_access', { 
                userId: user.id,
                filePath,
                ip: event.headers['x-forwarded-for']
            });
            return createErrorResponse(new Error('Access denied: You can only transcribe your own files'), 403);
        }
        
        logger.info('File ownership verified', { userId: user.id, filePath });

        const bucketName = 'audio-files';
        logger.info('Downloading file from storage', { bucket: bucketName, filePath });
        
        // Download file with timeout
        const downloadWithTimeout = withTimeout(
            () => supabase.storage.from(bucketName).download(filePath),
            30000 // 30 second timeout
        );
        
        const { data: blobData, error: downloadError } = await downloadWithTimeout();

        if (downloadError) {
            logger.error('File download failed', { 
                bucket: bucketName,
                filePath,
                userId: user.id 
            }, downloadError);
            return createErrorResponse(
                new Error('Failed to download audio file from storage'), 
                500
            );
        }

        logger.info('File downloaded successfully', { 
            bucket: bucketName,
            filePath,
            fileSize: blobData.size 
        });

        const assembly = new AssemblyAI({
            apiKey: process.env.ASSEMBLYAI_API_KEY,
        });

        logger.info('Starting transcription with AssemblyAI', { userId: user.id });
        logger.apiCall('AssemblyAI', 'transcripts.submit', { 
            speaker_labels: true,
            fileSize: blobData.size 
        });
        
        // Submit transcription with circuit breaker and timeout
        const transcriptWithTimeout = withTimeout(
            () => assemblyAIBreaker.execute(() => assembly.transcripts.submit({
                audio: blobData,
                speaker_labels: true,
                auto_chapters: false,
                filter_profanity: false,
                format_text: true
            })),
            120000 // 2 minute timeout for submission
        );
        
        const transcript = await transcriptWithTimeout();
        
        logger.info('Transcription submitted successfully', { 
            transcriptId: transcript.id,
            userId: user.id,
            status: transcript.status 
        });

        const responseData = {
            id: transcript.id,
            text: transcript.text,
            segments: transcript.words, 
            status: transcript.status,
            userId: user.id
        };
        
        // Add rate limit headers if available
        const additionalHeaders = context.rateLimitHeaders || {};
        additionalHeaders.origin = event.headers.origin;
        
        return createSuccessResponse(responseData, 200, additionalHeaders);

    } catch (error) {
        logger.error('Transcription request failed', {
            userId: event.user?.id,
            filePath: event.validatedData?.filePath,
            errorType: error.constructor.name
        }, error);
        
        // Determine appropriate status code
        let statusCode = 500;
        if (error.message.includes('Circuit breaker')) {
            statusCode = 503; // Service Unavailable
        } else if (error.message.includes('timed out')) {
            statusCode = 408; // Request Timeout
        } else if (error.message.includes('Authorization') || 
                   error.message.includes('Access denied')) {
            statusCode = 403; // Forbidden
        }
        
        return createErrorResponse(error, statusCode);
    }
});