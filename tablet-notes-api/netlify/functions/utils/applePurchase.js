const {
  SignedDataVerifier,
  Environment
} = require('@apple/app-store-server-library');

// Product → tier mapping. Must stay in sync with the client's product IDs
// (SubscriptionService.productIds). The tier is derived here from the
// *verified* productId — never from anything the client claims (TAB-47).
const PRODUCT_TIERS = {
  'com.tabletnotes.premium.monthly': 'premium',
  'com.tabletnotes.premium.annual': 'premium'
};

const DEFAULT_BUNDLE_ID = 'Creative-Native.TabletNotes';

/**
 * Loads Apple root CA certificates (DER) from base64 env vars. StoreKit signed
 * transactions chain to Apple Root CA - G3; G2 is accepted as a fallback for
 * older chains. Returns [] when none are configured — callers must fail closed.
 */
function loadAppleRootCerts(env = process.env) {
  const certs = [];
  for (const key of ['APPLE_ROOT_CA_G3', 'APPLE_ROOT_CA_G2']) {
    const value = env[key];
    if (value && value.trim()) {
      certs.push(Buffer.from(value.trim(), 'base64'));
    }
  }
  return certs;
}

/**
 * Verifies a StoreKit signed transaction (JWS) offline against Apple's root
 * certs and returns the decoded, trusted payload. Tries Production first, then
 * Sandbox (TestFlight / dev), matching Apple's recommended verification flow.
 *
 * @param {object} deps - injectable for testing (VerifierClass, environments).
 * @throws if the signature/chain is invalid in every environment.
 */
async function verifySignedTransaction(signedTransaction, {
  rootCerts,
  bundleId,
  appAppleId,
  VerifierClass = SignedDataVerifier,
  environments = [Environment.PRODUCTION, Environment.SANDBOX]
}) {
  let lastError;
  for (const environment of environments) {
    try {
      const verifier = new VerifierClass(rootCerts, false, environment, bundleId, appAppleId);
      return await verifier.verifyAndDecodeTransaction(signedTransaction);
    } catch (error) {
      lastError = error;
    }
  }
  throw lastError || new Error('Transaction verification failed');
}

/**
 * Derives the entitlement to persist from a verified transaction payload.
 * Validates the payload belongs to this app and a known product before
 * trusting it. Pure — unit-testable without Apple infrastructure.
 *
 * @throws if the bundle or product doesn't match.
 */
function resolveEntitlement(payload, {
  bundleId = DEFAULT_BUNDLE_ID,
  productTiers = PRODUCT_TIERS,
  now = Date.now(),
  expectedAccountToken = null
} = {}) {
  if (payload.bundleId !== bundleId) {
    throw new Error(`Bundle ID mismatch: ${payload.bundleId}`);
  }

  // Bind the transaction to the authenticated account. The client sets
  // appAccountToken = the user's id at purchase; without this check a user
  // could replay their own signed transaction against another account to grant
  // it premium. Apple lowercases the token, so compare case-insensitively.
  if (expectedAccountToken) {
    const token = (payload.appAccountToken || '').toLowerCase();
    if (token !== String(expectedAccountToken).toLowerCase()) {
      throw new Error('Transaction is not bound to this account');
    }
  }

  const tier = productTiers[payload.productId];
  if (!tier) {
    throw new Error(`Unknown product: ${payload.productId}`);
  }

  const expiresDate = typeof payload.expiresDate === 'number' ? payload.expiresDate : null;
  const purchaseDate = typeof payload.purchaseDate === 'number' ? payload.purchaseDate : null;
  // A subscription with no/expired expiry is no longer active. getSubscriptionState
  // already treats non-'active' or expired as free, but we record the true state.
  const isActive = expiresDate !== null && expiresDate > now;

  return {
    tier,
    status: isActive ? 'active' : 'expired',
    productId: payload.productId,
    originalTransactionId: payload.originalTransactionId || null,
    purchaseDate: purchaseDate !== null ? new Date(purchaseDate).toISOString() : null,
    expiresDate: expiresDate !== null ? new Date(expiresDate).toISOString() : null
  };
}

module.exports = {
  PRODUCT_TIERS,
  DEFAULT_BUNDLE_ID,
  loadAppleRootCerts,
  verifySignedTransaction,
  resolveEntitlement
};
