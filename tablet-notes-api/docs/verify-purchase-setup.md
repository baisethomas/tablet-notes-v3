# Setup: StoreKit purchase verification (`verify-purchase`)

`verify-purchase` validates a StoreKit signed transaction against Apple's root
certificate **offline** (no App Store Connect API key required) and writes the
resulting entitlement to `profiles`. Until the env below is set, the function
**fails closed** — it returns `503` and grants nothing, so no one is ever
marked premium without a verified purchase.

## Required Netlify environment variables

| Var | Required | Value |
|-----|----------|-------|
| `APPLE_ROOT_CA_G3` | **Yes** | Base64 of Apple Root CA - G3 (DER `.cer`) |
| `APPLE_ROOT_CA_G2` | Optional | Base64 of Apple Root CA - G2 (older chains) |
| `APPLE_BUNDLE_ID` | Optional | Defaults to `Creative-Native.TabletNotes` |
| `APPLE_APP_APPLE_ID` | Optional | Numeric App Store app ID (only needed if online checks are enabled later) |

`SUPABASE_URL` / `SUPABASE_SERVICE_ROLE_KEY` are already configured.

## Obtaining the root cert (public)

```bash
# Apple Root CA - G3 (used to sign StoreKit JWS transactions)
curl -sO https://www.apple.com/certificateauthority/AppleRootCA-G3.cer
base64 -i AppleRootCA-G3.cer | tr -d '\n' > approotg3.b64
# paste the contents of approotg3.b64 as APPLE_ROOT_CA_G3 in Netlify

# (optional) Apple Root CA - G2
curl -sO https://www.apple.com/certificateauthority/AppleRootCA-G2.cer
base64 -i AppleRootCA-G2.cer | tr -d '\n'   # -> APPLE_ROOT_CA_G2
```

Set them with the Netlify CLI (from `tablet-notes-api/`, already linked):

```bash
netlify env:set APPLE_ROOT_CA_G3 "$(cat approotg3.b64)"
netlify deploy --prod
```

## Verifying it works

1. Sandbox account, build that includes the client change (sends
   `transaction.jwsRepresentation` to `/api/verify-purchase`).
2. Purchase the monthly or annual product.
3. Check the `profiles` row: `subscription_tier = premium`,
   `subscription_status = active`, `subscription_product_id` set,
   `subscription_expiry` in the future.
4. Confirm `getSubscriptionState` now returns `isPaid: true` for that user
   (premium summaries + live transcription unlocked).

Sandbox purchases are signed in the **Sandbox** environment; the verifier
tries Production first, then Sandbox, so both work without config changes.

## Notes / follow-ups

- This is **purchase-time** verification. Lifecycle events (renewals, refunds,
  expirations) are reconciled client-side via `Transaction.currentEntitlements`
  on launch, which re-posts to `verify-purchase`. Server-push handling of those
  events (App Store Server Notifications V2) is a possible follow-up and would
  require an App Store Connect API key.
- Subscription fields are writable **only** through this verified endpoint.
  `update-profile` (usage counters) explicitly ignores any `subscription_*`
  fields a client might send.
