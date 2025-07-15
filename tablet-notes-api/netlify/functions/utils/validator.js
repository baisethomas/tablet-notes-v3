const Joi = require('joi');

// File type validation
const ALLOWED_AUDIO_TYPES = [
  'audio/mpeg', 'audio/mp3', 'audio/wav', 'audio/m4a', 'audio/aac',
  'audio/ogg', 'audio/webm', 'audio/flac'
];

const ALLOWED_AUDIO_EXTENSIONS = [
  '.mp3', '.wav', '.m4a', '.aac', '.ogg', '.webm', '.flac'
];

// Size limits (in bytes)
const LIMITS = {
  AUDIO_FILE_SIZE: 500 * 1024 * 1024, // 500MB
  TEXT_LENGTH: 100000, // 100k characters
  FILENAME_LENGTH: 255,
  SUMMARY_TEXT_LENGTH: 50000, // 50k characters for summarization
  API_REQUEST_SIZE: 10 * 1024 * 1024 // 10MB general request size
};

// Validation schemas
const schemas = {
  // File upload validation
  fileUpload: Joi.object({
    fileName: Joi.string()
      .trim()
      .min(1)
      .max(LIMITS.FILENAME_LENGTH)
      .pattern(/^[a-zA-Z0-9._-]+$/)
      .required()
      .messages({
        'string.pattern.base': 'Filename contains invalid characters. Only letters, numbers, dots, underscores, and hyphens are allowed.',
        'string.max': `Filename must be less than ${LIMITS.FILENAME_LENGTH} characters.`
      }),
    
    filePath: Joi.string()
      .trim()
      .min(1)
      .max(500)
      .required(),
    
    contentType: Joi.string()
      .valid(...ALLOWED_AUDIO_TYPES)
      .required()
      .messages({
        'any.only': `File type must be one of: ${ALLOWED_AUDIO_TYPES.join(', ')}`
      }),
    
    fileSize: Joi.number()
      .integer()
      .min(1)
      .max(LIMITS.AUDIO_FILE_SIZE)
      .required()
      .messages({
        'number.max': `File size must be less than ${Math.round(LIMITS.AUDIO_FILE_SIZE / 1024 / 1024)}MB`
      })
  }),

  // Transcription request validation
  transcription: Joi.object({
    filePath: Joi.string()
      .trim()
      .min(1)
      .max(500)
      .required(),
    
    language: Joi.string()
      .trim()
      .min(2)
      .max(10)
      .default('en')
      .optional(),
    
    webhookUrl: Joi.string()
      .uri()
      .optional(),
    
    options: Joi.object({
      speaker_labels: Joi.boolean().default(true),
      auto_chapters: Joi.boolean().default(false),
      filter_profanity: Joi.boolean().default(false),
      format_text: Joi.boolean().default(true)
    }).optional()
  }),

  // Summarization request validation
  summarization: Joi.object({
    text: Joi.string()
      .trim()
      .min(50)
      .max(LIMITS.SUMMARY_TEXT_LENGTH)
      .required()
      .messages({
        'string.min': 'Text must be at least 50 characters long for summarization.',
        'string.max': `Text must be less than ${LIMITS.SUMMARY_TEXT_LENGTH} characters.`
      }),
    
    type: Joi.string()
      .valid('sermon', 'general', 'notes')
      .default('sermon'),
    
    length: Joi.string()
      .valid('short', 'medium', 'long')
      .default('medium'),
    
    includeScripture: Joi.boolean()
      .default(true),
    
    tone: Joi.string()
      .valid('formal', 'conversational', 'academic')
      .default('conversational')
  }),

  // Bible API request validation
  bibleApi: Joi.object({
    endpoint: Joi.string()
      .trim()
      .min(1)
      .max(200)
      .required(),
    
    method: Joi.string()
      .valid('GET', 'POST')
      .default('GET'),
    
    bibleId: Joi.string()
      .trim()
      .min(10)
      .max(50)
      .optional(),
    
    query: Joi.object()
      .max(10) // Limit query parameters
      .optional()
  }),

  // Live transcription token request
  liveToken: Joi.object({
    sampleRate: Joi.number()
      .integer()
      .min(8000)
      .max(48000)
      .default(16000),
    
    channels: Joi.number()
      .integer()
      .min(1)
      .max(2)
      .default(1)
  }),

  // General authentication validation
  auth: Joi.object({
    authorization: Joi.string()
      .pattern(/^Bearer\s+[\w\-._~+/]+=*$/)
      .required()
      .messages({
        'string.pattern.base': 'Invalid authorization header format. Expected "Bearer <token>"'
      })
  })
};

class Validator {
  /**
   * Validate request data against a schema
   * @param {Object} data - Data to validate
   * @param {string} schemaName - Name of the schema to use
   * @param {Object} options - Joi validation options
   * @returns {Object} Validation result
   */
  static validate(data, schemaName, options = {}) {
    const schema = schemas[schemaName];
    if (!schema) {
      throw new Error(`Unknown validation schema: ${schemaName}`);
    }

    const defaultOptions = {
      abortEarly: false,
      stripUnknown: true,
      convert: true
    };

    const result = schema.validate(data, { ...defaultOptions, ...options });
    
    if (result.error) {
      const errors = result.error.details.map(detail => ({
        field: detail.path.join('.'),
        message: detail.message,
        value: detail.context?.value
      }));

      return {
        valid: false,
        errors,
        data: null
      };
    }

    return {
      valid: true,
      errors: null,
      data: result.value
    };
  }

  /**
   * Validate file upload specifically
   * @param {string} fileName - Name of the file
   * @param {string} contentType - MIME type
   * @param {number} fileSize - Size in bytes
   * @returns {Object} Validation result
   */
  static validateFileUpload(fileName, contentType, fileSize) {
    // Check file extension
    const hasValidExtension = ALLOWED_AUDIO_EXTENSIONS.some(ext => 
      fileName.toLowerCase().endsWith(ext)
    );

    if (!hasValidExtension) {
      return {
        valid: false,
        errors: [{
          field: 'fileName',
          message: `File extension must be one of: ${ALLOWED_AUDIO_EXTENSIONS.join(', ')}`,
          value: fileName
        }]
      };
    }

    // Validate using schema
    return this.validate({
      fileName,
      contentType,
      fileSize,
      filePath: 'temp' // Placeholder for schema validation
    }, 'fileUpload');
  }

  /**
   * Sanitize text input to prevent injection attacks
   * @param {string} text - Text to sanitize
   * @param {Object} options - Sanitization options
   * @returns {string} Sanitized text
   */
  static sanitizeText(text, options = {}) {
    if (typeof text !== 'string') {
      return '';
    }

    const {
      maxLength = LIMITS.TEXT_LENGTH,
      allowHtml = false,
      allowNewlines = true
    } = options;

    let sanitized = text.trim();

    // Truncate if too long
    if (sanitized.length > maxLength) {
      sanitized = sanitized.substring(0, maxLength);
    }

    // Remove or escape HTML if not allowed
    if (!allowHtml) {
      sanitized = sanitized
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#x27;')
        .replace(/\//g, '&#x2F;');
    }

    // Handle newlines
    if (!allowNewlines) {
      sanitized = sanitized.replace(/[\r\n]/g, ' ');
    }

    // Remove control characters except tabs and newlines
    sanitized = sanitized.replace(/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/g, '');

    return sanitized;
  }

  /**
   * Validate request size
   * @param {Object} event - Netlify event object
   * @returns {Object} Validation result
   */
  static validateRequestSize(event) {
    const contentLength = parseInt(event.headers['content-length'] || '0');
    
    if (contentLength > LIMITS.API_REQUEST_SIZE) {
      return {
        valid: false,
        error: `Request size ${Math.round(contentLength / 1024 / 1024)}MB exceeds limit of ${Math.round(LIMITS.API_REQUEST_SIZE / 1024 / 1024)}MB`
      };
    }

    return { valid: true };
  }

  /**
   * Validate user ID format
   * @param {string} userId - User ID to validate
   * @returns {boolean} Whether user ID is valid
   */
  static isValidUserId(userId) {
    if (!userId || typeof userId !== 'string') {
      return false;
    }

    // UUID format validation
    const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
    return uuidPattern.test(userId);
  }

  /**
   * Create validation middleware for Netlify functions
   * @param {string} schemaName - Schema to validate against
   * @param {string} source - Where to get data ('body', 'query', 'headers')
   * @returns {Function} Middleware function
   */
  static createValidationMiddleware(schemaName, source = 'body') {
    return (event) => {
      try {
        let data;
        
        switch (source) {
          case 'body':
            data = event.body ? JSON.parse(event.body) : {};
            break;
          case 'query':
            data = event.queryStringParameters || {};
            break;
          case 'headers':
            data = event.headers || {};
            break;
          default:
            throw new Error(`Invalid data source: ${source}`);
        }

        const validation = this.validate(data, schemaName);
        
        if (!validation.valid) {
          return {
            statusCode: 400,
            headers: {
              'Content-Type': 'application/json'
            },
            body: JSON.stringify({
              error: 'Validation failed',
              details: validation.errors,
              message: 'Request data is invalid or missing required fields'
            })
          };
        }

        // Attach validated data to event
        event.validatedData = validation.data;
        return null; // Continue processing

      } catch (error) {
        console.error('[ValidationMiddleware] Error:', error);
        return {
          statusCode: 400,
          headers: {
            'Content-Type': 'application/json'
          },
          body: JSON.stringify({
            error: 'Invalid request format',
            message: 'Request could not be parsed or validated'
          })
        };
      }
    };
  }
}

module.exports = {
  Validator,
  schemas,
  LIMITS,
  ALLOWED_AUDIO_TYPES,
  ALLOWED_AUDIO_EXTENSIONS
};