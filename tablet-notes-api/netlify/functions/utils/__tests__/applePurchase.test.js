const test = require('node:test');
const assert = require('node:assert/strict');
const {
  loadAppleRootCerts,
  verifySignedTransaction,
  resolveEntitlement,
  PRODUCT_TIERS,
  DEFAULT_BUNDLE_ID
} = require('../applePurchase');

const FUTURE = Date.UTC(2999, 0, 1);
const PAST = Date.UTC(2000, 0, 1);

function payload(overrides = {}) {
  return {
    bundleId: DEFAULT_BUNDLE_ID,
    productId: 'com.tabletnotes.premium.monthly',
    purchaseDate: Date.UTC(2026, 0, 1),
    expiresDate: FUTURE,
    originalTransactionId: 'orig-1',
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
