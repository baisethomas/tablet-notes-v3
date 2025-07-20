const { createClient } = require('@supabase/supabase-js');

// Security configuration
const SECURITY_CONFIG = {
  // CORS configuration based on environment
  cors: {
    development: [
      'http://localhost:3000',
      'http://localhost:8080',
      'http://127.0.0.1:3000',
      'https://localhost:3000'
    ],
    production: [
      'https://tabletnotes.io',
      'https://www.tabletnotes.io',
      'https://app.tabletnotes.io'
    ],
    // Netlify preview deploys
    preview: [
      /^https:\/\/.*--tabletnotes\.netlify\.app$/
    ]
  },
  
  // Security headers
  headers: {
    'X-Content-Type-Options': 'nosniff',
    'X-Frame-Options': 'DENY',
    'X-XSS-Protection': '1; mode=block',
    'Referrer-Policy': 'strict-origin-when-cross-origin',
    'Content-Security-Policy': "default-src 'self'; script-src 'none'; object-src 'none';",
    'Strict-Transport-Security': 'max-age=31536000; includeSubDomains'
  },
  
  // Request timeouts (in milliseconds)
  timeouts: {
    default: 30000, // 30 seconds
    upload: 300000, // 5 minutes for file uploads
    transcription: 600000, // 10 minutes for transcription
    summary: 120000 // 2 minutes for summary
  }
};

/**
 * Get allowed origins based on environment
 * @returns {Array} List of allowed origins
 */
function getAllowedOrigins() {
  const env = process.env.NODE_ENV || 'development';
  const customOrigins = process.env.ALLOWED_ORIGINS;
  
  if (customOrigins) {
    return customOrigins.split(',').map(origin => origin.trim());
  }
  
  switch (env) {
    case 'production':
      return SECURITY_CONFIG.cors.production;
    case 'development':
      return SECURITY_CONFIG.cors.development;
    default:
      return [...SECURITY_CONFIG.cors.development, ...SECURITY_CONFIG.cors.production];
  }
}

/**
 * Check if origin is allowed
 * @param {string} origin - Origin to check
 * @returns {boolean} Whether origin is allowed
 */
function isOriginAllowed(origin) {
  if (!origin) return false;
  
  const allowedOrigins = getAllowedOrigins();
  
  // Check exact matches
  if (allowedOrigins.includes(origin)) {
    return true;
  }
  
  // Check regex patterns (for preview deploys)
  return SECURITY_CONFIG.cors.preview.some(pattern => {
    if (pattern instanceof RegExp) {
      return pattern.test(origin);
    }
    return false;
  });
}

/**
 * Create CORS headers
 * @param {string} origin - Request origin
 * @param {string} method - Request method
 * @returns {Object} CORS headers
 */
function createCORSHeaders(origin, method = 'GET') {
  const headers = {
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type, Authorization, X-Requested-With',
    'Access-Control-Max-Age': '86400', // 24 hours
    'Vary': 'Origin'
  };
  
  // Only set origin if it's allowed
  if (isOriginAllowed(origin)) {
    headers['Access-Control-Allow-Origin'] = origin;
    headers['Access-Control-Allow-Credentials'] = 'true';
  } else {
    headers['Access-Control-Allow-Origin'] = 'null';
  }
  
  return headers;
}

/**
 * Create security headers
 * @returns {Object} Security headers
 */
function createSecurityHeaders() {
  return { ...SECURITY_CONFIG.headers };
}

/**
 * Handle CORS preflight requests
 * @param {Object} event - Netlify event object
 * @returns {Object|null} Response object for OPTIONS requests, null otherwise
 */
function handleCORS(event) {
  const origin = event.headers.origin || event.headers.Origin;
  const method = event.httpMethod;
  
  // Handle OPTIONS preflight requests
  if (method === 'OPTIONS') {
    return {
      statusCode: 200,
      headers: {
        ...createCORSHeaders(origin, method),
        ...createSecurityHeaders()
      },
      body: ''
    };
  }
  
  return null;
}

/**
 * Authenticate user using Supabase JWT
 * @param {string} authHeader - Authorization header value
 * @returns {Promise<Object>} User object or null
 */
async function authenticateUser(authHeader) {
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    throw new Error('Missing or invalid authorization header');
  }
  
  const token = authHeader.substring(7);
  
  try {
    // Initialize Supabase client
    const supabase = createClient(
      process.env.SUPABASE_URL,
      process.env.SUPABASE_ANON_KEY
    );
    
    // Verify the JWT token
    const { data: { user }, error } = await supabase.auth.getUser(token);
    
    if (error) {
      throw new Error(`Authentication failed: ${error.message}`);
    }
    
    if (!user) {
      throw new Error('Invalid token: user not found');
    }
    
    return user;
    
  } catch (error) {
    console.error('[Security] Authentication error:', error);
    throw new Error(`Authentication failed: ${error.message}`);
  }
}

/**
 * Create authentication middleware
 * @returns {Function} Middleware function
 */
function createAuthMiddleware() {
  return async (event) => {
    try {
      const authHeader = event.headers.authorization || event.headers.Authorization;
      
      if (!authHeader) {
        return {
          statusCode: 401,
          headers: {
            'Content-Type': 'application/json',
            ...createSecurityHeaders()
          },
          body: JSON.stringify({
            error: 'Unauthorized',
            message: 'Missing authorization header'
          })
        };
      }
      
      const user = await authenticateUser(authHeader);
      
      // Attach user to event for downstream use
      event.user = user;
      
      return null; // Continue processing
      
    } catch (error) {
      console.error('[AuthMiddleware] Error:', error);
      return {
        statusCode: 401,
        headers: {
          'Content-Type': 'application/json',
          ...createSecurityHeaders()
        },
        body: JSON.stringify({
          error: 'Unauthorized',
          message: error.message || 'Authentication failed'
        })
      };
    }
  };
}

/**
 * Check if user owns the resource (based on file path)
 * @param {Object} user - User object
 * @param {string} filePath - File path to check
 * @returns {boolean} Whether user owns the resource
 */
function checkResourceOwnership(user, filePath) {
  if (!user || !user.id || !filePath) {
    return false;
  }
  
  // File paths should start with user ID: {userId}/filename
  return filePath.startsWith(`${user.id}/`);
}

/**
 * Create timeout wrapper for async functions
 * @param {Function} fn - Function to wrap
 * @param {number} timeout - Timeout in milliseconds
 * @returns {Function} Wrapped function
 */
function withTimeout(fn, timeout) {
  return async (...args) => {
    return Promise.race([
      fn(...args),
      new Promise((_, reject) => 
        setTimeout(() => reject(new Error(`Operation timed out after ${timeout}ms`)), timeout)
      )
    ]);
  };
}

/**
 * Create circuit breaker for external API calls
 */
class CircuitBreaker {
  constructor(threshold = 5, timeout = 60000) {
    this.threshold = threshold; // Number of failures before opening
    this.timeout = timeout; // Time to wait before half-open
    this.failureCount = 0;
    this.state = 'CLOSED'; // CLOSED, OPEN, HALF_OPEN
    this.nextAttempt = Date.now();
  }
  
  async execute(fn, ...args) {
    if (this.state === 'OPEN') {
      if (Date.now() < this.nextAttempt) {
        throw new Error('Circuit breaker is OPEN');
      }
      this.state = 'HALF_OPEN';
    }
    
    try {
      const result = await fn(...args);
      this.onSuccess();
      return result;
    } catch (error) {
      this.onFailure();
      throw error;
    }
  }
  
  onSuccess() {
    this.failureCount = 0;
    this.state = 'CLOSED';
  }
  
  onFailure() {
    this.failureCount++;
    if (this.failureCount >= this.threshold) {
      this.state = 'OPEN';
      this.nextAttempt = Date.now() + this.timeout;
    }
  }
}

/**
 * Create a standardized error response
 * @param {Error} error - Error object
 * @param {number} statusCode - HTTP status code
 * @returns {Object} Netlify response object
 */
function createErrorResponse(error, statusCode = 500) {
  const isDevelopment = process.env.NODE_ENV === 'development';
  
  return {
    statusCode,
    headers: {
      'Content-Type': 'application/json',
      ...createSecurityHeaders()
    },
    body: JSON.stringify({
      error: error.name || 'Internal Server Error',
      message: error.message || 'An unexpected error occurred',
      ...(isDevelopment && { stack: error.stack }), // Only include stack in development
      timestamp: new Date().toISOString()
    })
  };
}

/**
 * Create a standardized success response
 * @param {Object} data - Response data
 * @param {number} statusCode - HTTP status code
 * @param {Object} additionalHeaders - Additional headers
 * @returns {Object} Netlify response object
 */
function createSuccessResponse(data, statusCode = 200, additionalHeaders = {}) {
  const origin = additionalHeaders.origin;
  
  return {
    statusCode,
    headers: {
      'Content-Type': 'application/json',
      ...createCORSHeaders(origin),
      ...createSecurityHeaders(),
      ...additionalHeaders
    },
    body: JSON.stringify({
      success: true,
      data,
      timestamp: new Date().toISOString()
    })
  };
}

module.exports = {
  handleCORS,
  createAuthMiddleware,
  authenticateUser,
  checkResourceOwnership,
  withTimeout,
  CircuitBreaker,
  createErrorResponse,
  createSuccessResponse,
  createCORSHeaders,
  createSecurityHeaders,
  isOriginAllowed,
  SECURITY_CONFIG
};