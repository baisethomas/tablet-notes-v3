---
name: ship-linear-issue
description: End-to-end workflow for shipping one Linear issue (TAB-NN) as one branch and one PR in TabletNotes — branch setup, implementation guardrails, verification, PR authoring, and review-round handling. Use when starting work on a TAB issue, when asked to "pick up TAB-NN", or when responding to owner review feedback on an open PR.
---

# Ship a Linear issue (TAB-NN)

The owner's invariant: **one issue = one branch = one PR, owner reviews and merges.** This skill walks the full loop. Do the phases in order; each has an exit gate.

## Phase 0 — Understand before touching code

1. Read the issue: `mcp__plugin_linear_linear__get_issue` with the TAB identifier. Note: title, description, priority, `gitBranchName`, acceptance criteria, linked PRs/comments.
2. Check for prior art — this repo has deep history and the issue may be partially done:
   ```bash
   git log --oneline --all --grep "TAB-NN"
   gh pr list --state all --search "TAB-NN"
   git branch -a | grep -i "tab-nn"
   ```
3. If the issue references a phase plan, read it (`docs/superpowers/plans/`). If it references prod symptoms ("61 stuck sermons", "notes not syncing"), verify the symptom with a read-only prod query (see CLAUDE.md §8) **before** designing a fix — several issues here turned out to have a different root cause than the issue text assumed.
4. Restate the root cause in one sentence. If you cannot, you are not ready to implement — keep diagnosing.

**Exit gate:** you can say what's broken, why, which files own it, and what "fixed" observably looks like.

## Phase 1 — Branch

```bash
git checkout main && git pull origin main
git checkout -b <gitBranchName-from-Linear>     # baise/tab-nn-short-slug
```
- If a local branch for this issue already exists, use it (rebase onto main) — do not create a second one, and never rename a branch that has an open PR even if Linear renamed the issue.
- Move the Linear issue to "In Progress" (`save_issue`).

## Phase 2 — Implement

Scope discipline:
- Touch only what the issue needs. Unrelated bug found → flag it (new Linear issue or spawn_task with file paths), do not fix it here.
- Backend + client fix pairs are allowed in one PR when they're the same issue (e.g. TAB-56 rounded timestamps on both sides) — same issue, same PR is fine; second issue, second PR.

Binding constraints (full list in CLAUDE.md §5–6; the ones violated most):
- No `MainActor.assumeIsolated`; no `AnyView`; no `@StateObject`/`@ObservedObject` on `@Observable`.
- Touching a `@Model` = migration event → note it now for the PR body.
- Backend: never return 2xx on partial failure; never delete-before-insert; fail closed; validate + rate-limit new endpoints.
- New Swift files need no `.pbxproj` edits (`fileSystemSynchronizedGroups`).

For a bug fix, write the regression test **first** and watch it fail — the owner expects a test that fails without the fix.

Commit as you go, imperative + scoped + tagged:
```
fix(sync): scope upload backoff per-user and per-endpoint (TAB-55)
test(sync): pull restores all sermons when one audio download fails (TAB-53)
```

## Phase 3 — Verify (all of it, actually run)

```bash
# iOS build (18.5 sim required)
xcodebuild build -scheme TabletNotes -destination 'platform=iOS Simulator,id=2BAC53A3-EC5B-40DE-A981-7F7A637A555E'

# iOS tests for the suites you touched
xcodebuild test -scheme TabletNotes -destination 'platform=iOS Simulator,id=<18.5-sim>' \
  -only-testing:TabletNotesTests/<Suite>

# API side, if tablet-notes-api/ changed
cd tablet-notes-api && npm test && node --check netlify/functions/<each-changed-fn>.js
```

Failure triage:
- A failing test → check the same test on `main` first. Known pre-existing: `SyncServiceMergeTests/syncDataIncludesOnlyDirtyChildScopesForExistingRemoteSermon`; `SermonServiceSaveTests` recovery tests (UserDefaults cross-pollution — pass in isolation). Name them in the PR if they show up; never claim "all tests pass" while hiding them, and never fix them inside this PR.
- Behavior that only shows on-device/simulator (recording, migration, restore UX) → use the `sim-verify` skill; if it needs a signed-in account, say so and list exact manual steps for the owner instead of claiming it verified.

**Exit gate:** build exit 0, relevant tests green (minus named pre-existing), regression test proven to fail-without/pass-with.

## Phase 4 — PR

```bash
git push -u origin <branch>
gh pr create --title "[TAB-NN] <short description>" --body "<template below>"
```

Body template (all sections, every time):
```markdown
## Problem
<user-visible symptom + root cause, one paragraph each>

## Fix
<what changed and why this approach; note alternatives rejected if any>

## Testing
- `xcodebuild build` — exit 0
- `<suite>` — N/N pass (pre-existing failures excluded: <name them or "none">)
- `npm test` — N/N  (if API touched)
- Regression test: `<name>` fails without fix, passes with

## Manual test steps
<numbered steps the owner can follow>

## Deploy / migration notes
<"Requires `netlify deploy --prod` from tablet-notes-api/ — inert until deployed" |
 "@Model changed: <lightweight-safe? why>" | "None">
```

Then: link the PR on the Linear issue, leave a one-line comment there summarizing state (e.g. "PR #NN open; backend fix inert until deploy").

**Do not merge. Ever.** The owner merges.

## Phase 5 — Review rounds

Owner review rounds are the norm (TAB-53 took five). For each round:
1. Address every finding — one or more commits per round, referencing the round in the message body if useful.
2. If you disagree, argue in a PR comment with evidence; don't silently drop the finding, don't cave silently either.
3. A finding may invalidate an earlier decision (a whole schema baseline got backed out here once). Prefer deleting your own wrong code over defending it.
4. **Update the PR description** to match the current diff — a stale description was itself a review finding once.
5. Re-run Phase 3 verification after every round. Push.
6. If a round reveals the issue was mis-scoped, propose the rescope on the Linear issue (title/description/acceptance) and get owner agreement — that happened with TAB-53 and was the right call.

## Phase 6 — After merge

- Backend files changed → the fix is **inert until `netlify deploy --prod`**. State this explicitly and track it as deploy debt (see `deploy-api` skill). Update the Linear issue: merged @ sha, deploy pending.
- Client-only → note which build/TestFlight it lands in.
- Move Linear status only to a state that's true (merged ≠ Done if deploy or device verification is pending).
