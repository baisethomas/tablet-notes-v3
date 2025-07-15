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

// Circuit breaker for Bible API
const bibleAPIBreaker = new CircuitBreaker(3, 60000);

exports.handler = withLogging('bible-api', async (event, context) => {
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

  if (event.httpMethod !== 'GET' && event.httpMethod !== 'POST') {
    return createErrorResponse(new Error('Method Not Allowed'), 405);
  }
  
  // Apply rate limiting
  const rateLimitMiddleware = createRateLimitMiddleware('bible');
  const rateLimitResponse = await rateLimitMiddleware(event, context);
  if (rateLimitResponse) {
    logger.rateLimit(event.user?.id || 'anonymous', 'bible', false, {
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

    // Get the Bible API key from environment variables
    const bibleApiKey = process.env.BIBLE_API_KEY;
    if (!bibleApiKey) {
      logger.error('Bible API key not configured');
      return createErrorResponse(new Error('Bible API service not available'), 503);
    }

    const baseURL = 'https://api.scripture.api.bible/v1';
    
    // Parse and validate request parameters
    let endpoint, requestMethod = 'GET';
    
    if (event.httpMethod === 'GET') {
      // Extract endpoint from query parameters
      endpoint = event.queryStringParameters?.endpoint;
    } else if (event.httpMethod === 'POST') {
      // Validate request body
      const validationMiddleware = Validator.createValidationMiddleware('bibleApi', 'body');
      const validationResponse = validationMiddleware(event);
      if (validationResponse) {
        logger.validationError(validationResponse.body ? JSON.parse(validationResponse.body).details : [], {
          userId: user.id
        });
        return validationResponse;
      }
      
      const { endpoint: ep, method } = event.validatedData;
      endpoint = ep;
      requestMethod = method || 'GET';
    }

    if (!endpoint) {
      logger.warn('No endpoint provided', { userId: user.id, method: event.httpMethod });
      return createErrorResponse(new Error('endpoint parameter is required'), 400);
    }
    
    // Sanitize endpoint to prevent injection
    const sanitizedEndpoint = Validator.sanitizeText(endpoint, {
      maxLength: 200,
      allowHtml: false,
      allowNewlines: false
    });
    
    if (sanitizedEndpoint !== endpoint) {
      logger.security('endpoint_sanitization', {
        userId: user.id,
        original: endpoint,
        sanitized: sanitizedEndpoint
      });
    }

    // Construct full URL
    const url = `${baseURL}/${sanitizedEndpoint}`;
    
    logger.info('Making Bible API request', {
      userId: user.id,
      method: requestMethod,
      endpoint: sanitizedEndpoint,
      url
    });
    
    logger.apiCall('BibleAPI', sanitizedEndpoint, {
      method: requestMethod,
      userId: user.id
    });

    // Make request to Bible API with circuit breaker and timeout
    const bibleAPIRequestWithTimeout = withTimeout(
      () => bibleAPIBreaker.execute(() => fetch(url, {
        method: requestMethod,
        headers: {
          'api-key': bibleApiKey,
          'Content-Type': 'application/json',
          'User-Agent': 'TabletNotes/1.0'
        }
      })),
      10000 // 10 second timeout
    );
    
    const response = await bibleAPIRequestWithTimeout();

    if (!response.ok) {
      const errorText = await response.text();
      logger.warn('Bible API returned error', {
        userId: user.id,
        status: response.status,
        statusText: response.statusText,
        endpoint: sanitizedEndpoint,
        errorText: errorText.substring(0, 500) // Truncate for logging
      });
      
      // Handle specific Bible API errors gracefully
      if (response.status === 404) {
        // Verse not found - return a proper response instead of throwing
        const responseData = {
          data: null,
          error: 'Verse not found',
          status: 404,
          userId: user.id,
          endpoint: sanitizedEndpoint
        };
        
        const additionalHeaders = context.rateLimitHeaders || {};
        additionalHeaders.origin = event.headers.origin;
        
        return createSuccessResponse(responseData, 200, additionalHeaders);
      } else if (response.status >= 400 && response.status < 500) {
        // Client error - return the error information
        const responseData = {
          data: null,
          error: `Bible API client error: ${response.status} ${response.statusText}`,
          details: errorText.substring(0, 200), // Truncate error details
          userId: user.id,
          endpoint: sanitizedEndpoint
        };
        
        const additionalHeaders = context.rateLimitHeaders || {};
        additionalHeaders.origin = event.headers.origin;
        
        return createSuccessResponse(responseData, 200, additionalHeaders);
      }
      
      throw new Error(`Bible API request failed: ${response.status} ${response.statusText}`);
    }

    const data = await response.json();
    
    logger.info('Bible API request completed successfully', {
      userId: user.id,
      endpoint: sanitizedEndpoint,
      responseSize: JSON.stringify(data).length,
      hasData: !!data.data
    });
    
    const responseData = {
      data,
      userId: user.id,
      endpoint: sanitizedEndpoint,
      metadata: {
        responseTime: Date.now() - logger.startTime,
        apiVersion: 'v1',
        cached: false
      }
    };
    
    // Add rate limit headers if available
    const additionalHeaders = context.rateLimitHeaders || {};
    additionalHeaders.origin = event.headers.origin;
    
    return createSuccessResponse(responseData, 200, additionalHeaders);

  } catch (error) {
    logger.error('Bible API request failed', {
      userId: event.user?.id,
      endpoint: event.queryStringParameters?.endpoint || event.validatedData?.endpoint,
      method: event.httpMethod,
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