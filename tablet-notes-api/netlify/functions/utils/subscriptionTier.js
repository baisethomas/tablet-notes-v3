const PAID_TIERS = ['pro', 'premium'];

/**
 * Resolves a user's effective subscription state from profiles — the single
 * source of truth for server-side tier checks (TAB-37).
 *
 * Fails closed: missing profile, missing fields, lookup errors, inactive
 * status, and expired subscriptions all resolve to free.
 *
 * @returns {Promise<{tier: string, isPaid: boolean}>} `tier` is the effective
 * tier ('free' unless the paid subscription is active and unexpired).
 */
async function getSubscriptionState({ supabase, userId, logger }) {
  try {
    const { data: profile, error } = await supabase
      .from('profiles')
      .select('subscription_tier, subscription_status, subscription_expiry')
      .eq('id', userId)
      .single();

    if (error || !profile) {
      logger.warn('Could not fetch profile; defaulting to free tier', {
        userId,
        error: error?.message
      });
      return { tier: 'free', isPaid: false };
    }

    const tier = profile.subscription_tier || 'free';
    const status = profile.subscription_status || 'free';
    const expiry = profile.subscription_expiry ? new Date(profile.subscription_expiry) : null;

    const isPaid = PAID_TIERS.includes(tier) &&
      status === 'active' &&
      (!expiry || expiry > new Date());

    return { tier: isPaid ? tier : 'free', isPaid };
  } catch (lookupError) {
    logger.warn('Profile lookup failed; defaulting to free tier', {
      userId,
      error: lookupError.message
    });
    return { tier: 'free', isPaid: false };
  }
}

module.exports = { getSubscriptionState, PAID_TIERS };
