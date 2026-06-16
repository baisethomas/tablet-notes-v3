const test = require('node:test');
const assert = require('node:assert/strict');
const {
  loadAppleRootCerts,
  verifySignedTransaction,
  resolveEntitlement,
  PRODUCT_TIERS,
  DEFAULT_BUNDLE_ID
} = require('../applePurchase');
const { SignedDataVerifier, Environment } = require('@apple/app-store-server-library');

const FUTURE = Date.UTC(2999, 0, 1);
const PAST = Date.UTC(2000, 0, 1);
const ACCOUNT = '11111111-1111-1111-1111-111111111111';

function payload(overrides = {}) {
  return {
    bundleId: DEFAULT_BUNDLE_ID,
    productId: 'com.tabletnotes.premium.monthly',
    purchaseDate: Date.UTC(2026, 0, 1),
    expiresDate: FUTURE,
    originalTransactionId: 'orig-1',
    appAccountToken: ACCOUNT,
    ...overrides
  };
}

test('resolveEntitlement maps a valid active subscription to premium/active', () => {
  const e = resolveEntitlement(payload(), { now: Date.UTC(2026, 5, 1) });
  assert.equal(e.tier, 'premium');
  assert.equal(e.status, 'active');
  assert.equal(e.productId, 'com.tabletnotes.premium.monthly');
  assert.equal(e.expiresDate, new Date(FUTURE).toISOString());
  assert.equal(e.originalTransactionId, 'orig-1');
});

test('resolveEntitlement marks an expired subscription as expired', () => {
  const e = resolveEntitlement(payload({ expiresDate: PAST }), { now: Date.UTC(2026, 5, 1) });
  assert.equal(e.tier, 'premium');
  assert.equal(e.status, 'expired');
});

test('resolveEntitlement rejects a transaction for another bundle (spoofing guard)', () => {
  assert.throws(
    () => resolveEntitlement(payload({ bundleId: 'com.evil.app' })),
    /Bundle ID mismatch/
  );
});

test('resolveEntitlement rejects an unknown product', () => {
  assert.throws(
    () => resolveEntitlement(payload({ productId: 'com.tabletnotes.free.lol' })),
    /Unknown product/
  );
});

test('resolveEntitlement treats a missing expiry as not active', () => {
  const e = resolveEntitlement(payload({ expiresDate: undefined }));
  assert.equal(e.status, 'expired');
  assert.equal(e.expiresDate, null);
});

test('annual product also resolves to premium', () => {
  const e = resolveEntitlement(payload({ productId: 'com.tabletnotes.premium.annual' }), { now: Date.UTC(2026, 5, 1) });
  assert.equal(e.tier, 'premium');
  assert.equal(PRODUCT_TIERS['com.tabletnotes.premium.annual'], 'premium');
});

test('loadAppleRootCerts returns [] when unconfigured (caller fails closed)', () => {
  assert.deepEqual(loadAppleRootCerts({}), []);
});

test('loadAppleRootCerts decodes configured base64 certs', () => {
  const der = Buffer.from('fake-cert-bytes');
  const certs = loadAppleRootCerts({ APPLE_ROOT_CA_G3: der.toString('base64') });
  assert.equal(certs.length, 1);
  assert.ok(certs[0].equals(der));
});

test('verifySignedTransaction tries Sandbox after Production fails', async () => {
  const attempts = [];
  class FakeVerifier {
    constructor(_certs, _online, environment) { this.environment = environment; }
    async verifyAndDecodeTransaction(jws) {
      attempts.push(this.environment);
      if (this.environment === 'Production') throw new Error('wrong environment');
      return { ...payload(), _jws: jws };
    }
  }

  const result = await verifySignedTransaction('signed-jws', {
    rootCerts: [Buffer.from('x')],
    bundleId: DEFAULT_BUNDLE_ID,
    VerifierClass: FakeVerifier,
    environments: ['Production', 'Sandbox']
  });

  assert.deepEqual(attempts, ['Production', 'Sandbox']);
  assert.equal(result._jws, 'signed-jws');
});

test('verifySignedTransaction throws when verification fails in all environments', async () => {
  class AlwaysFails {
    async verifyAndDecodeTransaction() { throw new Error('bad signature'); }
  }

  await assert.rejects(
    () => verifySignedTransaction('jws', {
      rootCerts: [Buffer.from('x')],
      bundleId: DEFAULT_BUNDLE_ID,
      VerifierClass: AlwaysFails,
      environments: ['Production', 'Sandbox']
    }),
    /bad signature/
  );
});

test('resolveEntitlement accepts a transaction bound to the authed account', () => {
  const e = resolveEntitlement(payload(), { now: Date.UTC(2026, 5, 1), expectedAccountToken: ACCOUNT });
  assert.equal(e.tier, 'premium');
  assert.equal(e.status, 'active');
});

test('resolveEntitlement matches the account token case-insensitively', () => {
  const e = resolveEntitlement(payload({ appAccountToken: ACCOUNT.toUpperCase() }), {
    now: Date.UTC(2026, 5, 1),
    expectedAccountToken: ACCOUNT
  });
  assert.equal(e.tier, 'premium');
});

test('resolveEntitlement rejects a transaction bound to a different account (replay guard)', () => {
  assert.throws(
    () => resolveEntitlement(payload(), { expectedAccountToken: '22222222-2222-2222-2222-222222222222' }),
    /not bound to this account/
  );
});

test('resolveEntitlement rejects a transaction with no account token when one is expected', () => {
  assert.throws(
    () => resolveEntitlement(payload({ appAccountToken: undefined }), { expectedAccountToken: ACCOUNT }),
    /not bound to this account/
  );
});

// Pins the library contract the endpoint relies on: a Production verifier
// cannot be constructed without appAppleId, so APPLE_APP_APPLE_ID must be
// required (verify-purchase fails closed when it is absent). Uses a throwaway
// self-signed cert only so construction reaches the appAppleId check (cert
// parsing runs first); it is NOT an Apple cert and verifies nothing.
const THROWAWAY_DER = Buffer.from(
  'MIIDCTCCAfGgAwIBAgIUacVzhRMnL+Sn0OJrq+UND6t5NDYwDQYJKoZIhvcNAQELBQAwFDESMBAGA1UEAwwJdGVzdC1yb290MB4XDTI2MDYxNjA3MTI1NFoXDTI2MDYxNzA3MTI1NFowFDESMBAGA1UEAwwJdGVzdC1yb290MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAqVuV7Z0gXG6Ts17KosXk1hI7OKTziouvrvthl2xMDY3EoYeIjpcv6VEaz1r7+lrIMzBN9n6swXQWUN+XhwYExSgXN54/LEGVwXGIGDVnS9Jvn7oEO8BCkJudc+JZPcQoBHI3bhxhHkvVQuBXgcki9vlwxqPA7g+ZiiDswBTYk3pUS0EZXSeTZ6X9FrPKa/792QeZlV/rMl0yJL3ENI5LZM+nAjrlLVPRCc3eYbanweZdLg4itRWVEt5OXcQOKTD8XiRPemy6+tv0Z4It8sIv8dX6bWJ3v17DtDnM9sTAyaHdHC25aNY1yn8kyVjNqVowztGkZ2TonAL+8y7FOGZOcwIDAQABo1MwUTAdBgNVHQ4EFgQUMe5o66LW6u0os8AW1zWhHLHFAJcwHwYDVR0jBBgwFoAUMe5o66LW6u0os8AW1zWhHLHFAJcwDwYDVR0TAQH/BAUwAwEB/zANBgkqhkiG9w0BAQsFAAOCAQEAAEefxwqGrJtoO6GZlRxFW8pbodrgiZxUB0H/gYNoFNRZdGT70vUSekYPicKDuzHjDDTHazoA4+2AGBAF0R7JvI28L4OtWVUPIUA5+TKLbaE4kpU8wqQXt3KCrqyQJRsZZrbbPl6qWHb8ZZWK+D3xp710uOO8oSOjK2m86taPe8ohhgJsSQtC6nnCI2LFriC/6G37EqG4pAdGL0QbgsaMLwFak17y8a8aa/w/mC4pLd+2PzC6DrNkcFmhyp4GYeXToJMvhurj1CNcifadgYCYhWYsWw0j10ALPJxariH2XtFXfWTicyVaASmm+FmqJJRzjUB6L5LqqZZuVQhWXLz2qA==',
  'base64'
);

test('SignedDataVerifier requires appAppleId for the Production environment', () => {
  assert.throws(
    () => new SignedDataVerifier([THROWAWAY_DER], false, Environment.PRODUCTION, DEFAULT_BUNDLE_ID, undefined),
    /appAppleId is required/
  );
});
