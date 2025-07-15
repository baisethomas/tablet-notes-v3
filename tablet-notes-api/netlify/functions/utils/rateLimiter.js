const { Redis } = require('@upstash/redis');

// Rate limiting configuration
const RATE_LIMITS = {
  // General API calls - per user per minute
  general: {
    windowMs: 60 * 1000, // 1 minute
    maxRequests: 60, // 60 requests per minute per user
    keyPrefix: 'rate_limit:general:'
  },
  
  // File uploads - per user per hour
  upload: {
    windowMs: 60 * 60 * 1000, // 1 hour
    maxRequests: 10, // 10 uploads per hour per user
    keyPrefix: 'rate_limit:upload:'
  },
  
  // Transcription requests - per user per hour  
  transcription: {
    windowMs: 60 * 60 * 1000, // 1 hour
    maxRequests: 20, // 20 transcriptions per hour per user
    keyPrefix: 'rate_limit:transcription:'
  },
  
  // Summarization requests - per user per hour
  summarization: {
    windowMs: 60 * 60 * 1000, // 1 hour
    maxRequests: 50, // 50 summaries per hour per user
    keyPrefix: 'rate_limit:summarization:'
  },
  
  // Bible API requests - per user per minute
  bible: {
    windowMs: 60 * 1000, // 1 minute
    maxRequests: 30, // 30 requests per minute per user
    keyPrefix: 'rate_limit:bible:'
  },
  
  // Per-IP rate limiting (additional protection)
  ip: {
    windowMs: 60 * 1000, // 1 minute
    maxRequests: 100, // 100 requests per minute per IP
    keyPrefix: 'rate_limit:ip:'
  }
};

class RateLimiter {
  constructor() {
    // Initialize Redis client only if URL is provided
    this.redis = null;
    if (process.env.UPSTASH_REDIS_REST_URL && process.env.UPSTASH_REDIS_REST_TOKEN) {
      this.redis = new Redis({
        url: process.env.UPSTASH_REDIS_REST_URL,
        token: process.env.UPSTASH_REDIS_REST_TOKEN,
      });
    }
  }

  /**
   * Check if a request should be rate limited
   * @param {string} identifier - User ID or IP address
   * @param {string} limitType - Type of rate limit to apply
   * @param {string} ip - Client IP address for additional protection
   * @returns {Promise<{allowed: boolean, remaining: number, resetTime: number, error?: string}>}
   */
  async checkLimit(identifier, limitType = 'general', ip = null) {
    try {
      // If Redis is not configured, allow all requests (fallback)
      if (!this.redis) {
        console.warn('[RateLimiter] Redis not configured, allowing all requests');
        return { allowed: true, remaining: Infinity, resetTime: Date.now() };
      }

      const config = RATE_LIMITS[limitType];
      if (!config) {
        throw new Error(`Invalid rate limit type: ${limitType}`);
      }

      const now = Date.now();
      const window = Math.floor(now / config.windowMs);
      
      // Check user-based rate limit
      const userKey = `${config.keyPrefix}${identifier}:${window}`;
      const userCount = await this.redis.incr(userKey);
      
      // Set expiration for the key
      if (userCount === 1) {
        await this.redis.expire(userKey, Math.ceil(config.windowMs / 1000));
      }

      // Check IP-based rate limit if IP is provided
      let ipAllowed = true;
      if (ip) {
        const ipConfig = RATE_LIMITS.ip;
        const ipWindow = Math.floor(now / ipConfig.windowMs);
        const ipKey = `${ipConfig.keyPrefix}${ip}:${ipWindow}`;
        const ipCount = await this.redis.incr(ipKey);
        
        if (ipCount === 1) {
          await this.redis.expire(ipKey, Math.ceil(ipConfig.windowMs / 1000));
        }
        
        ipAllowed = ipCount <= ipConfig.maxRequests;
      }

      const userAllowed = userCount <= config.maxRequests;
      const allowed = userAllowed && ipAllowed;
      
      const result = {
        allowed,
        remaining: Math.max(0, config.maxRequests - userCount),
        resetTime: (window + 1) * config.windowMs,
        currentCount: userCount,
        maxRequests: config.maxRequests
      };

      if (!allowed) {
        result.error = !userAllowed 
          ? `Rate limit exceeded for user. ${userCount}/${config.maxRequests} requests in window.`
          : `Rate limit exceeded for IP address.`;
      }

      return result;

    } catch (error) {
      console.error('[RateLimiter] Error checking rate limit:', error);
      // In case of Redis errors, allow the request but log the error
      return { 
        allowed: true, 
        remaining: 0, 
        resetTime: Date.now(),
        error: `Rate limiter error: ${error.message}`
      };
    }
  }

  /**
   * Get current rate limit status without incrementing
   * @param {string} identifier - User ID or IP address
   * @param {string} limitType - Type of rate limit to check
   * @returns {Promise<{current: number, remaining: number, resetTime: number}>}
   */
  async getStatus(identifier, limitType = 'general') {
    try {
      if (!this.redis) {
        return { current: 0, remaining: Infinity, resetTime: Date.now() };
      }

      const config = RATE_LIMITS[limitType];
      if (!config) {
        throw new Error(`Invalid rate limit type: ${limitType}`);
      }

      const now = Date.now();
      const window = Math.floor(now / config.windowMs);
      const key = `${config.keyPrefix}${identifier}:${window}`;
      
      const current = await this.redis.get(key) || 0;
      
      return {
        current: parseInt(current),
        remaining: Math.max(0, config.maxRequests - current),
        resetTime: (window + 1) * config.windowMs
      };

    } catch (error) {
      console.error('[RateLimiter] Error getting status:', error);
      return { current: 0, remaining: 0, resetTime: Date.now() };
    }
  }

  /**
   * Reset rate limit for a specific identifier (admin function)
   * @param {string} identifier - User ID or IP address
   * @param {string} limitType - Type of rate limit to reset
   * @returns {Promise<boolean>}
   */
  async reset(identifier, limitType = 'general') {
    try {
      if (!this.redis) {
        return true;
      }

      const config = RATE_LIMITS[limitType];
      if (!config) {
        throw new Error(`Invalid rate limit type: ${limitType}`);
      }

      const now = Date.now();
      const window = Math.floor(now / config.windowMs);
      const key = `${config.keyPrefix}${identifier}:${window}`;
      
      await this.redis.del(key);
      return true;

    } catch (error) {
      console.error('[RateLimiter] Error resetting rate limit:', error);
      return false;
    }
  }
}

// Export singleton instance
const rateLimiter = new RateLimiter();

/**
 * Express-style middleware for rate limiting
 * @param {string} limitType - Type of rate limit to apply
 * @returns {Function} Middleware function
 */
function createRateLimitMiddleware(limitType = 'general') {
  return async (event, context) => {
    try {
      // Extract user ID from authorization header
      const authHeader = event.headers.authorization || event.headers.Authorization;
      let userId = 'anonymous';
      
      if (authHeader && authHeader.startsWith('Bearer ')) {
        try {
          // Extract user ID from JWT token (basic parsing)
          const token = authHeader.substring(7);
          const payload = JSON.parse(Buffer.from(token.split('.')[1], 'base64').toString());
          userId = payload.sub || payload.user_id || 'anonymous';
        } catch (e) {
          // If token parsing fails, use anonymous
          userId = 'anonymous';
        }
      }

      // Get client IP
      const clientIP = event.headers['x-forwarded-for'] || 
                      event.headers['x-real-ip'] || 
                      event.headers['client-ip'] ||
                      'unknown';

      // Check rate limit
      const result = await rateLimiter.checkLimit(userId, limitType, clientIP);

      if (!result.allowed) {
        return {
          statusCode: 429,
          headers: {
            'Content-Type': 'application/json',
            'X-RateLimit-Limit': result.maxRequests?.toString() || '0',
            'X-RateLimit-Remaining': '0',
            'X-RateLimit-Reset': Math.ceil(result.resetTime / 1000).toString(),
            'Retry-After': Math.ceil((result.resetTime - Date.now()) / 1000).toString()
          },
          body: JSON.stringify({
            error: 'Rate limit exceeded',
            message: result.error || 'Too many requests',
            retryAfter: Math.ceil((result.resetTime - Date.now()) / 1000)
          })
        };
      }

      // Add rate limit headers to successful responses
      context.rateLimitHeaders = {
        'X-RateLimit-Limit': result.maxRequests?.toString() || '0',
        'X-RateLimit-Remaining': result.remaining.toString(),
        'X-RateLimit-Reset': Math.ceil(result.resetTime / 1000).toString()
      };

      return null; // Continue processing
    } catch (error) {
      console.error('[RateLimitMiddleware] Error:', error);
      // Don't block requests on rate limiter errors
      return null;
    }
  };
}

module.exports = {
  rateLimiter,
  createRateLimitMiddleware,
  RATE_LIMITS
};