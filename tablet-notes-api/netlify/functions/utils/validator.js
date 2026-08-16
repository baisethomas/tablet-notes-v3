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
  SUMMARY_TEXT_LENGTH: 150000, // Supports long-form pro transcripts up to the 90-minute recording limit
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
      }),

    // Optional: clients that send it get a stable, resumable object path
    // (TAB-73). Optional so already-shipped builds keep working.
    sermonLocalId: Joi.string()
      .trim()
      .guid({ version: ['uuidv4', 'uuidv1', 'uuidv5'] })
      .optional()
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

    // Free-form service label chosen in the app ("Sunday Service", "Bible
    // Study", "Youth Group", ...). Structure-validated (allowlisted characters,
    // bounded length), never text-escaped — it is interpolated into the LLM
    // prompt, not into HTML. Without this key, stripUnknown removed the field
    // and every user got the default sermon prompt (TAB-68).
    serviceType: Joi.string()
      .trim()
      .pattern(/^[A-Za-z0-9 \-']{1,50}$/)
      .optional()
      .messages({
        'string.pattern.base': 'serviceType may only contain letters, numbers, spaces, hyphens, and apostrophes (max 50 characters).'
      }),

    length: Joi.string()
      .valid('short', 'medium', 'long')
      .default('medium'),
    
    includeScripture: Joi.boolean()
      .default(true),
    
    tone: Joi.string()
      .valid('formal', 'conversational', 'academic')
      .default('conversational')
  }),

  // Processing job creation (TAB-72): POST /api/jobs
  processingJob: Joi.object({
    // The client's local sermon UUID; the server resolves it to sermons.id.
    sermonLocalId: Joi.string()
      .guid({ version: ['uuidv4', 'uuidv5'] })
      .required()
      .messages({ 'string.guid': 'sermonLocalId must be a UUID.' }),

    // Optional storage path. When omitted the server uses the sermon row's own
    // audio_file_path, which it wrote itself and therefore trusts — that is the
    // preferred call shape. When supplied, ownership is enforced against the
    // authenticated user's id prefix (checkResourceOwnership) before use.
    filePath: Joi.string()
      .trim()
      .min(1)
      .max(500)
      .optional(),

    kind: Joi.string()
      .valid('transcription', 'summary')
      .default('transcription'),

    // Deliberate retry of an exhausted (`dead`) job. Defaults false, so an
    // automatic sweep never resurrects one — that loop is TAB-85. Only a user
    // asking for a retry should spend provider calls on a job that already
    // failed every attempt.
    // .strict() because Joi otherwise coerces the string "true" to true,
    // which would quietly defeat the exact-boolean check in
    // isExhaustedWithoutRetry. A retry is a deliberate act; spell it.
    retry: Joi.boolean().strict().default(false)
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
   * Sanitize free text destined for an LLM prompt.
   *
   * HTML entity escaping is the wrong transform for this sink (named failure
   * mode #7): it mangles every apostrophe/quote/slash in a transcript
   * ("God's" -> "God&#x27;s"), degrading summary quality and inflating token
   * cost ~4x per escaped character. LLM-bound text needs length bounds and
   * control-character stripping only — the model consumes it as plain text.
   * @param {string} text - Text to sanitize
   * @param {Object} options - { maxLength }
   * @returns {string} Sanitized text (never HTML-escaped)
   */
  static sanitizeLLMText(text, options = {}) {
    if (typeof text !== 'string') {
      return '';
    }

    const { maxLength = LIMITS.TEXT_LENGTH } = options;

    let sanitized = text.trim();

    if (sanitized.length > maxLength) {
      sanitized = sanitized.substring(0, maxLength);
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
