const test = require('node:test');
const assert = require('node:assert/strict');
const { getSubscriptionState } = require('../subscriptionTier');

const silentLogger = { info() {}, warn() {}, error() {} };

function fakeSupabase(profileResult) {
  return {
    from() {
      return {
        select() {
          return {
            eq() {
              return {
                async single() {
                  return profileResult;
                }
              };
            }
          };
        }
      };
    }
  };
}

function stateFor(profileResult) {
  return getSubscriptionState({
    supabase: fakeSupabase(profileResult),
    userId: 'user-1',
    logger: silentLogger
  });
}

test('active unexpired premium subscription is paid', async () => {
  const state = await stateFor({
    data: {
      subscription_tier: 'premium',
      subscription_status: 'active',
      subscription_expiry: new Date(Date.now() + 86_400_000).toISOString()
    },
    error: null
  });

  assert.deepEqual(state, { tier: 'premium', isPaid: true });
});

test('active pro subscription without expiry is paid', async () => {
  const state = await stateFor({
    data: { subscription_tier: 'pro', subscription_status: 'active', subscription_expiry: null },
    error: null
  });

  assert.deepEqual(state, { tier: 'pro', isPaid: true });
});

test('expired subscription resolves to free', async () => {
  const state = await stateFor({
    data: {
      subscription_tier: 'premium',
      subscription_status: 'active',
      subscription_expiry: new Date(Date.now() - 86_400_000).toISOString()
    },
    error: null
  });

  assert.deepEqual(state, { tier: 'free', isPaid: false });
});

test('inactive status resolves to free', async () => {
  const state = await stateFor({
    data: { subscription_tier: 'premium', subscription_status: 'canceled', subscription_expiry: null },
    error: null
  });

  assert.deepEqual(state, { tier: 'free', isPaid: false });
});

test('missing profile resolves to free (no pro default)', async () => {
  const state = await stateFor({ data: null, error: { message: 'not found' } });

  assert.deepEqual(state, { tier: 'free', isPaid: false });
});

test('missing tier metadata resolves to free', async () => {
  const state = await stateFor({
    data: { subscription_tier: null, subscription_status: null, subscription_expiry: null },
    error: null
  });

  assert.deepEqual(state, { tier: 'free', isPaid: false });
});

test('lookup exception resolves to free', async () => {
  const supabase = {
    from() {
      throw new Error('connection refused');
    }
  };

  const state = await getSubscriptionState({ supabase, userId: 'user-1', logger: silentLogger });
  assert.deepEqual(state, { tier: 'free', isPaid: false });
});
