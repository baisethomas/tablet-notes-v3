const { createClient } = require('@supabase/supabase-js');
const {
  handleCORS,
  createAuthMiddleware,
  createErrorResponse,
  createSuccessResponse
} = require('./utils/security');
const { withLogging } = require('./utils/logger');
const {
  loadAppleRootCerts,
  verifySignedTransaction,
  resolveEntitlement,
  DEFAULT_BUNDLE_ID
} = require('./utils/applePurchase');

// Verifies a StoreKit signed transaction with Apple and writes the resulting
// entitlement to profiles. The tier is derived from the cryptographically
// verified transaction, never from anything the client claims — so a user
// cannot self-grant premium by POSTing a tier (TAB-47 / protects TAB-37).
exports.handler = withLogging('verify-purchase', async (event, context) => {
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
    const signedTransaction = body.signedTransaction;

    if (!signedTransaction || typeof signedTransaction !== 'string') {
      return createErrorResponse(new Error('Missing required field: signedTransaction'), 400);
    }

    // Fail closed if the verifier isn't provisioned — never grant entitlement
    // without a real Apple-verified transaction. appAppleId is required: the
    // library mandates it to construct a Production verifier, and real App
    // Store transactions are signed in Production.
    const rootCerts = loadAppleRootCerts(process.env);
    const appAppleId = Number(process.env.APPLE_APP_APPLE_ID);
    if (rootCerts.length === 0 || !Number.isFinite(appAppleId)) {
      logger.error('Purchase verification not configured', {
        hasRootCerts: rootCerts.length > 0,
        hasAppAppleId: Number.isFinite(appAppleId)
      });
      return createErrorResponse(new Error('Purchase verification is not available'), 503);
    }

    const bundleId = process.env.APPLE_BUNDLE_ID || DEFAULT_BUNDLE_ID;

    let payload;
    try {
      payload = await verifySignedTransaction(signedTransaction, { rootCerts, bundleId, appAppleId });
    } catch (verifyError) {
      logger.security('purchase_verification_failed', {
        userId: user.id,
        error: verifyError.message
      });
      return createErrorResponse(new Error('Could not verify purchase'), 400);
    }

    let entitlement;
    try {
      entitlement = resolveEntitlement(payload, { bundleId, expectedAccountToken: user.id });
    } catch (resolveError) {
      // Verified signature but wrong app/product/account — treat as a spoof or
      // cross-account replay attempt.
      logger.security('purchase_entitlement_rejected', {
        userId: user.id,
        error: resolveError.message,
        productId: payload.productId,
        payloadBundleId: payload.bundleId
      });
      return createErrorResponse(new Error('Purchase is not valid for this app'), 400);
    }

    const supabase = createClient(supabaseUrl, supabaseKey);
    const { error: updateError } = await supabase
      .from('profiles')
      .update({
        subscription_tier: entitlement.tier,
        subscription_status: entitlement.status,
        subscription_product_id: entitlement.productId,
        subscription_purchase_date: entitlement.purchaseDate,
        subscription_expiry: entitlement.expiresDate,
        subscription_renewal_date: entitlement.expiresDate,
        updated_at: new Date().toISOString()
      })
      .eq('id', user.id);

    if (updateError) {
      logger.error('Failed to persist verified entitlement', {
        userId: user.id,
        error: updateError.message
      });
      return createErrorResponse(new Error(updateError.message), 500);
    }

    logger.info('Verified purchase persisted', {
      userId: user.id,
      productId: entitlement.productId,
      status: entitlement.status,
      expiresDate: entitlement.expiresDate
    });

    return createSuccessResponse({
      subscriptionTier: entitlement.tier,
      subscriptionStatus: entitlement.status,
      subscriptionProductId: entitlement.productId,
      subscriptionPurchaseDate: entitlement.purchaseDate,
      subscriptionExpiry: entitlement.expiresDate,
      subscriptionRenewalDate: entitlement.expiresDate
    }, 200);

  } catch (error) {
    logger.error('Purchase verification failed', {
      userId: event.user?.id,
      error: error.message,
      stack: error.stack
    });
    return createErrorResponse(error, 500);
  }
});
