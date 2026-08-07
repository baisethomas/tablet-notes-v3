const { createRateLimitMiddleware } = require('./rateLimiter');
const { Validator } = require('./validator');
const {
  handleCORS,
  createAuthMiddleware,
  createErrorResponse
} = require('./security');
const { withLogging } = require('./logger');

/**
 * Composed middleware for Netlify functions (TAB-72).
 *
 * Every function in this codebase hand-rolls the same ~40-line preamble, which
 * is why 6 of 13 ended up with no rate limiting, no schema validation, and no
 * timeout at all (docs/rewrite/01-consolidated-audit.md S2-1) — protection was
 * opt-in and applied by copy-paste. This makes it opt-OUT.
 *
 * Order matters and matches the existing hand-rolled stacks exactly:
 *   CORS preflight -> method guard -> request size -> rate limit -> auth ->
 *   schema validation -> handler
 *
 * Rate limiting deliberately runs BEFORE auth: the limiter derives its per-user
 * key by parsing the JWT itself, and moving it after auth would let unauthorized
 * traffic bypass the limit entirely.
 *
 * @param {string} name              Function name for the logger.
 * @param {object} options
 * @param {string[]} [options.methods=['POST']]  Allowed HTTP methods.
 * @param {string|null} [options.rateLimit='general']  RATE_LIMITS key, or null to skip.
 * @param {boolean} [options.auth=true]  Require a Supabase Bearer token (sets event.user).
 * @param {string|null} [options.schema=null]  Joi schema name (sets event.validatedData).
 * @param {boolean} [options.checkSize=true]  Enforce the request-size cap.
 * @param {Function} handler         async (event, context) => response
 */
function withDefaults(name, options, handler) {
  const {
    methods = ['POST'],
    rateLimit = 'general',
    auth = true,
    schema = null,
    checkSize = true
  } = options || {};

  return withLogging(name, async (event, context) => {
    const logger = event.logger;

    const corsResponse = handleCORS(event);
    if (corsResponse) return corsResponse;

    if (!methods.includes(event.httpMethod)) {
      return createErrorResponse(new Error('Method Not Allowed'), 405);
    }

    if (checkSize) {
      const sizeValidation = Validator.validateRequestSize(event);
      if (!sizeValidation.valid) {
        logger?.warn('Request size validation failed', { error: sizeValidation.error });
        return createErrorResponse(new Error(sizeValidation.error), 413);
      }
    }

    if (rateLimit) {
      const rateLimitResponse = await createRateLimitMiddleware(rateLimit)(event, context);
      if (rateLimitResponse) {
        logger?.rateLimit(event.user?.id || 'anonymous', rateLimit, false);
        return rateLimitResponse;
      }
    }

    if (auth) {
      // createAuthMiddleware returns async (event) — normalized here so callers
      // never have to remember the arity difference from the rate limiter.
      const authResponse = await createAuthMiddleware()(event);
      if (authResponse) {
        logger?.security('authentication_failed', {
          reason: 'missing_or_invalid_token',
          ip: event.headers['x-forwarded-for']
        });
        return authResponse;
      }
    }

    if (schema) {
      const validationResponse = Validator.createValidationMiddleware(schema, 'body')(event);
      if (validationResponse) {
        let details = [];
        try {
          details = validationResponse.body ? JSON.parse(validationResponse.body).details : [];
        } catch (_) {
          details = [];
        }
        logger?.validationError(details, { userId: event.user?.id });
        return validationResponse;
      }
    }

    const result = await handler(event, context);

    // withLogging dereferences result.statusCode unguarded; a handler that falls
    // off the end would throw inside the logger and mask the real bug.
    if (!result || typeof result.statusCode !== 'number') {
      logger?.error('Handler returned no response', { name });
      return createErrorResponse(new Error('Internal Server Error'), 500);
    }

    return result;
  });
}

module.exports = { withDefaults };
