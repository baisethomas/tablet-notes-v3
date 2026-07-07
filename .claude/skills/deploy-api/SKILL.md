---
name: deploy-api
description: Safely deploy the TabletNotes Netlify backend (tablet-notes-api/) to production and verify the deploy — preflight checks, env-var gates, smoke tests, prod-data verification, and deploy-debt accounting. Use when asked to deploy, when checking whether a merged backend fix is actually live, or when auditing what's merged-but-undeployed.
---

# Deploy & verify the Netlify backend

**Core fact: Netlify prod (`comfy-daffodil-7ecc55`) does NOT auto-deploy from GitHub.** Every merged backend change is inert until `netlify deploy --prod` runs from `tablet-notes-api/` (the linked directory). Fixes have sat merged-but-dead for weeks here; "is it fixed?" always means checking merged vs deployed vs verified.

**Deploying prod requires explicit owner go-ahead for this specific deploy.** If you don't have it, run Phases 0–1 (audit + preflight), report readiness, and stop.

## Phase 0 — What would this deploy ship? (deploy-debt audit)

A prod deploy ships **everything** merged to main under `tablet-notes-api/` since the last deploy, not just the fix you care about.

```bash
cd /Users/baisethomas/Dev/tablet-notes-v3/tablet-notes-api
netlify status                                    # confirm linked site: comfy-daffodil-7ecc55
netlify api listSiteDeploys --data '{"site_id":"03c45e87-848e-46dc-82a3-29dd21f11714"}' \
  | head -100                                     # find last prod deploy's created_at / sha
git log --oneline <last-deployed-sha>..origin/main -- . | cat   # everything that will go live
```

List each TAB issue in that range. If anything in the range is env-var-gated or half-finished, flag it before proceeding. Known standing gates (check current session memory for updates):
- Upstash Redis vars absent in prod → rate limiter uses in-memory hard-cap fallback (intended fail-closed behavior).
- `verify-purchase` returns 503 until `APPLE_ROOT_CA_G3` + `APPLE_APP_APPLE_ID` are set (intended fail-closed behavior — deploying it "broken" is correct).

## Phase 1 — Preflight

```bash
git checkout main && git pull origin main         # deploy from clean, current main ONLY
git status --short                                # no local modifications under tablet-notes-api/
cd tablet-notes-api
npm test                                          # all suites green — do not deploy on red
for f in $(git diff --name-only <last-deployed-sha>..HEAD -- netlify/functions | grep '\.js$'); do
  node --check "../$f" || echo "SYNTAX FAIL: $f"
done
netlify env:list --context production             # every env var new code reads must exist
```

Never deploy from a feature branch or a dirty tree — the deploy snapshots the working directory, not git.

**Exit gate:** clean main, tests green, env vars accounted for (present, or the code demonstrably fails closed without them), owner go-ahead in hand.

## Phase 2 — Deploy

```bash
cd tablet-notes-api && netlify deploy --prod
```
Capture the deploy URL/ID from output for the record.

## Phase 3 — Smoke test (immediately, every time)

Unauthenticated probes — expect **auth/validation rejections**, never 500s:

```bash
B=https://comfy-daffodil-7ecc55.netlify.app/.netlify/functions
curl -s -o /dev/null -w "create-sermon: %{http_code}\n" -X POST $B/create-sermon -H "Content-Type: application/json" -d '{}'
curl -s -o /dev/null -w "get-sermons:   %{http_code}\n" $B/get-sermons
curl -s -o /dev/null -w "transcribe:    %{http_code}\n" -X POST $B/transcribe -d '{}'
curl -s -o /dev/null -w "live-token:    %{http_code}\n" -X POST $B/assemblyai-live-token
curl -s -o /dev/null -w "verify-purch:  %{http_code}\n" -X POST $B/verify-purchase -d '{}'
```
Reading the codes: 400/401/405 = healthy (rejected correctly). 503 on verify-purchase = expected while Apple env vars are unset. **Any 500 = the deploy broke something — investigate now; if a previously-healthy endpoint 500s, tell the owner immediately and treat rollback (redeploy last good sha) as the default.**

Then hit the specific endpoint(s) this deploy changed with a request shaped to exercise the fix path as far as auth allows.

## Phase 4 — Verify the fix against prod data

Generic smoke isn't verification. For the fix that motivated the deploy, define the observable prod outcome and query it (read-only — see CLAUDE.md §8 for service-key access):

```bash
supabase projects api-keys --project-ref ubghnmenxbhhlpxvypea    # service key (READ-ONLY use)
curl -s "https://ubghnmenxbhhlpxvypea.supabase.co/rest/v1/<table>?select=...&limit=..." \
  -H "apikey: $KEY" -H "Authorization: Bearer $KEY"
```

Examples of the standard here:
- Rate-limit change → confirm a burst no longer 429s at the old threshold.
- Notes-timestamp fix → after a device syncs, new `notes` rows exist with non-zero integer timestamps.
- Backfill-adjacent fix → before/after counts of the stuck population.

Some verifications need a real device/account (owner action) — if so, write the exact steps and expected observations for the owner; don't mark verified.

## Phase 5 — Record it

- Comment on the relevant Linear issue(s): deployed @ <sha> on <date>, smoke results, verification result or the pending manual step.
- Update session memory if it tracks deploy state for these issues.
- If Phase 0 found other issues going live in this deploy, note on their issues that they're now deployed too.

## Anti-patterns (each has burned this project)

- Declaring a backend fix done at merge. **Merged ≠ live.**
- Deploying with untested working-tree edits, or from a feature branch.
- Skipping the smoke curls because "the tests passed" — unit tests cover `utils/`, not the function wiring, env access, or Netlify runtime.
- Treating a fail-closed 503 as a deploy failure — check whether it's an intended env-var gate first.
- Verifying with "the endpoint returns 200" when the fix is about data: check the rows.
