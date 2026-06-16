const { createClient } = require('@supabase/supabase-js');
const {
  handleCORS,
  createAuthMiddleware,
  createErrorResponse,
  createSuccessResponse
} = require('./utils/security');
const { withLogging } = require('./utils/logger');

// Writes non-privileged profile fields (usage counters) for the authenticated
// user. Subscription/entitlement fields are deliberately NOT writable here —
// they can only be set by verify-purchase after Apple verification, so this
// endpoint can never be used to self-grant premium (TAB-47).
const ALLOWED_FIELDS = new Set([
  'monthly_recording_count',
  'monthly_recording_minutes',
  'current_storage_used_gb',
  'monthly_export_count',
  'last_usage_reset_date'
]);

exports.handler = withLogging('update-profile', async (event, context) => {
  const logger = event.logger;

  const corsResponse = handleCORS(event);
  if (corsResponse) return corsResponse;

  if (event.httpMethod !== 'POST') {
    return createErrorResponse(new Error('Method Not Allowed'), 405);
  }

  const authMiddleware = createAuthMiddleware();
  const authResponse = await authMiddleware(event);
  if (authResponse) return authResponse;

  try {
    const supabaseUrl = process.env.SUPABASE_URL;
    const supabaseKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
    if (!supabaseUrl || !supabaseKey) {
      logger.error('Missing Supabase configuration');
      return createErrorResponse(new Error('Server configuration error'), 500);
    }

    const user = event.user;
    const body = JSON.parse(event.body || '{}');

    const patch = {};
    for (const [key, value] of Object.entries(body)) {
      if (ALLOWED_FIELDS.has(key) && value !== undefined && value !== null) {
        patch[key] = value;
      }
    }

    // If a client sent subscription fields, ignore them and note it — those are
    // only ever set via verified purchases.
    const rejected = Object.keys(body).filter(
      k => k.startsWith('subscription_') && body[k] !== undefined && body[k] !== null
    );
    if (rejected.length > 0) {
      logger.info('Ignoring subscription fields on update-profile (use verify-purchase)', {
        userId: user.id,
        ignored: rejected
      });
    }

    if (Object.keys(patch).length === 0) {
      return createSuccessResponse({ updated: false }, 200);
    }

    patch.updated_at = new Date().toISOString();

    const supabase = createClient(supabaseUrl, supabaseKey);
    const { error: updateError } = await supabase
      .from('profiles')
      .update(patch)
      .eq('id', user.id);

    if (updateError) {
      logger.error('Failed to update profile', {
        userId: user.id,
        error: updateError.message
      });
      return createErrorResponse(new Error(updateError.message), 500);
    }

    return createSuccessResponse({ updated: true, fields: Object.keys(patch) }, 200);

  } catch (error) {
    logger.error('Profile update failed', {
      userId: event.user?.id,
      error: error.message,
      stack: error.stack
    });
    return createErrorResponse(error, 500);
  }
});
