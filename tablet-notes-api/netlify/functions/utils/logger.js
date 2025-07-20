// Structured logging utility for Netlify Functions
const LOG_LEVELS = {
  ERROR: 0,
  WARN: 1,
  INFO: 2,
  DEBUG: 3
};

const LOG_LEVEL_NAMES = ['ERROR', 'WARN', 'INFO', 'DEBUG'];

class Logger {
  constructor(context = 'unknown', level = 'INFO') {
    this.context = context;
    this.level = LOG_LEVELS[level.toUpperCase()] || LOG_LEVELS.INFO;
    this.startTime = Date.now();
  }

  /**
   * Create a child logger with additional context
   * @param {string} childContext - Additional context
   * @returns {Logger} Child logger instance
   */
  child(childContext) {
    return new Logger(`${this.context}:${childContext}`, LOG_LEVEL_NAMES[this.level]);
  }

  /**
   * Log a message at the specified level
   * @param {number} level - Log level
   * @param {string} message - Log message
   * @param {Object} meta - Additional metadata
   * @param {Error} error - Optional error object
   */
  log(level, message, meta = {}, error = null) {
    if (level > this.level) {
      return; // Skip if below current log level
    }

    const timestamp = new Date().toISOString();
    const elapsed = Date.now() - this.startTime;
    
    const logEntry = {
      timestamp,
      level: LOG_LEVEL_NAMES[level],
      context: this.context,
      message,
      elapsed: `${elapsed}ms`,
      ...meta
    };

    // Add error details if provided
    if (error) {
      logEntry.error = {
        name: error.name,
        message: error.message,
        stack: error.stack
      };
    }

    // Add performance warning for slow operations
    if (elapsed > 5000) { // 5 seconds
      logEntry.performance_warning = true;
    }

    // Use appropriate console method based on level
    switch (level) {
      case LOG_LEVELS.ERROR:
        console.error(JSON.stringify(logEntry));
        break;
      case LOG_LEVELS.WARN:
        console.warn(JSON.stringify(logEntry));
        break;
      case LOG_LEVELS.DEBUG:
        console.debug(JSON.stringify(logEntry));
        break;
      default:
        console.log(JSON.stringify(logEntry));
    }
  }

  /**
   * Log error message
   * @param {string} message - Error message
   * @param {Object} meta - Additional metadata
   * @param {Error} error - Error object
   */
  error(message, meta = {}, error = null) {
    this.log(LOG_LEVELS.ERROR, message, meta, error);
  }

  /**
   * Log warning message
   * @param {string} message - Warning message
   * @param {Object} meta - Additional metadata
   */
  warn(message, meta = {}) {
    this.log(LOG_LEVELS.WARN, message, meta);
  }

  /**
   * Log info message
   * @param {string} message - Info message
   * @param {Object} meta - Additional metadata
   */
  info(message, meta = {}) {
    this.log(LOG_LEVELS.INFO, message, meta);
  }

  /**
   * Log debug message
   * @param {string} message - Debug message
   * @param {Object} meta - Additional metadata
   */
  debug(message, meta = {}) {
    this.log(LOG_LEVELS.DEBUG, message, meta);
  }

  /**
   * Log function start
   * @param {Object} event - Netlify event object
   */
  functionStart(event) {
    this.info('Function started', {
      method: event.httpMethod,
      path: event.path,
      userAgent: event.headers['user-agent'],
      ip: event.headers['x-forwarded-for'] || event.headers['x-real-ip'] || 'unknown',
      contentLength: event.headers['content-length'],
      userId: event.user?.id || 'anonymous'
    });
  }

  /**
   * Log function end with performance metrics
   * @param {number} statusCode - HTTP status code
   * @param {Object} meta - Additional metadata
   */
  functionEnd(statusCode, meta = {}) {
    const duration = Date.now() - this.startTime;
    
    this.info('Function completed', {
      statusCode,
      duration: `${duration}ms`,
      ...meta
    });

    // Log performance warning for slow functions
    if (duration > 10000) { // 10 seconds
      this.warn('Slow function detected', {
        duration: `${duration}ms`,
        threshold: '10000ms'
      });
    }
  }

  /**
   * Log API call to external service
   * @param {string} service - Service name
   * @param {string} endpoint - API endpoint
   * @param {Object} meta - Additional metadata
   */
  apiCall(service, endpoint, meta = {}) {
    this.info('External API call', {
      service,
      endpoint,
      ...meta
    });
  }

  /**
   * Log database operation
   * @param {string} operation - Database operation
   * @param {string} table - Table name
   * @param {Object} meta - Additional metadata
   */
  dbOperation(operation, table, meta = {}) {
    this.info('Database operation', {
      operation,
      table,
      ...meta
    });
  }

  /**
   * Log rate limit event
   * @param {string} userId - User ID
   * @param {string} limitType - Type of rate limit
   * @param {boolean} allowed - Whether request was allowed
   * @param {Object} meta - Additional metadata
   */
  rateLimit(userId, limitType, allowed, meta = {}) {
    const level = allowed ? LOG_LEVELS.DEBUG : LOG_LEVELS.WARN;
    const message = allowed ? 'Rate limit check passed' : 'Rate limit exceeded';
    
    this.log(level, message, {
      userId,
      limitType,
      allowed,
      ...meta
    });
  }

  /**
   * Log security event
   * @param {string} event - Security event type
   * @param {Object} meta - Additional metadata
   */
  security(event, meta = {}) {
    this.warn('Security event', {
      event,
      ...meta
    });
  }

  /**
   * Log validation failure
   * @param {Array} errors - Validation errors
   * @param {Object} meta - Additional metadata
   */
  validationError(errors, meta = {}) {
    this.warn('Validation failed', {
      errors,
      errorCount: errors.length,
      ...meta
    });
  }
}

/**
 * Create logger middleware for Netlify functions
 * @param {string} functionName - Name of the function
 * @returns {Function} Middleware function
 */
function createLoggerMiddleware(functionName) {
  return (event, context) => {
    const logger = new Logger(functionName, process.env.LOG_LEVEL || 'INFO');
    
    // Attach logger to event for downstream use
    event.logger = logger;
    
    // Log function start
    logger.functionStart(event);
    
    return null; // Continue processing
  };
}

/**
 * Wrap a function with logging
 * @param {string} functionName - Name of the function
 * @param {Function} handler - Function handler
 * @returns {Function} Wrapped handler
 */
function withLogging(functionName, handler) {
  return async (event, context) => {
    const logger = new Logger(functionName, process.env.LOG_LEVEL || 'INFO');
    event.logger = logger;
    
    try {
      logger.functionStart(event);
      
      const result = await handler(event, context);
      
      logger.functionEnd(result.statusCode, {
        success: result.statusCode < 400
      });
      
      return result;
      
    } catch (error) {
      logger.error('Function error', {
        errorName: error.name,
        errorMessage: error.message
      }, error);
      
      logger.functionEnd(500, {
        success: false,
        error: error.message
      });
      
      throw error;
    }
  };
}

/**
 * Log metrics for monitoring and alerting
 * @param {string} metric - Metric name
 * @param {number} value - Metric value
 * @param {Object} tags - Metric tags
 */
function logMetric(metric, value, tags = {}) {
  const metricEntry = {
    timestamp: new Date().toISOString(),
    type: 'metric',
    metric,
    value,
    tags
  };
  
  console.log(JSON.stringify(metricEntry));
}

/**
 * Log business event for analytics
 * @param {string} event - Event name
 * @param {Object} properties - Event properties
 * @param {string} userId - User ID
 */
function logEvent(event, properties = {}, userId = null) {
  const eventEntry = {
    timestamp: new Date().toISOString(),
    type: 'event',
    event,
    properties,
    userId
  };
  
  console.log(JSON.stringify(eventEntry));
}

module.exports = {
  Logger,
  createLoggerMiddleware,
  withLogging,
  logMetric,
  logEvent,
  LOG_LEVELS
};