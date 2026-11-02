# AGENTS.md — Canonical Working Rules for This Repository
<!-- ratchet-version: 1.2.0 -->

<!--
Ratchet (https://github.com/baisethomas/Ratchet) model-agnostic operating contract.
Any coding agent entering this repo reads this first, then the files it names.
Tool-specific files (`CLAUDE.md`, `CODEX.md`) point here and must not duplicate these rules.
-->

## Read order for a fresh agent

1. This file.
2. `docs/OPERATING-MANUAL.md` — the TabletNotes operating manual: repo map, exact commands, house style, backend rules, deploy reality, prod access, the named failure modes, the quality bar, and escalation rules. It is binding and it is model-agnostic; it lived at `TabletNotes/CLAUDE.md` until Ratchet adoption.
3. The adapter for the current harness, when one exists (`CODEX.md` for Codex; Claude Code loads `CLAUDE.md` before this file).
4. `.ratchet/STATE.md` — current state of this branch/workstream.
5. `.ratchet/DECISIONS.md` — durable decisions with rationale. Do not reopen them accidentally.
6. The Linear issue you are shipping (one issue = one branch = one PR), and `.claude/skills/ship-linear-issue/SKILL.md` for the end-to-end loop.

## Ratchet invariants

1. **Model independence.** A fresh agent must be able to work without knowing which model worked previously.
2. **Human is not the memory bus.** Routine handoff context belongs in the repo, not in the user's head.
3. **Memory stays small.** Never store chat transcripts or duplicate facts that are safely inferable from code, tests, Git history, or linked protected systems.
4. **Git owns integration truth.** Ratchet does not create a second live synchronization system beside Git. Branches/worktrees may carry different current state until they are integrated.
5. **Durable decisions survive handoffs.** Accepted rationale is never silently deleted or rewritten.
6. **Agents cannot silently expand authority.** Shared-state, irreversible, or high-impact actions still require the appropriate human gate.
7. **Sensitive information never becomes durable project memory.** Store sanitized references, not secrets or protected data.

## Before any edit

- Read `.ratchet/STATE.md` and `.ratchet/DECISIONS.md` before planning.
- Tool adapters: after this file, read the adapter for your tool if one exists at the repo root (`CLAUDE.md` for Claude Code, `CODEX.md` for Codex). Adapters add tool specifics only; this file wins any conflict.
- Treat `STATE.md` as the current state of this branch/workstream, not guaranteed global state across every branch or clone.
- Read the files you'll change AND their call sites before forming a plan. The repo is context the user didn't type.
- For anything beyond a trivial change, state the plan before editing.
- Resolve three things first: what behavior changes (intent), what's allowed to change (blast radius), and what proves it's done (passing test, reproduced-then-fixed bug, green build, or other explicit check).
- Write the definition of done as a checkable predicate before the first edit. It may be found wrong and replaced with the owner's agreement; it is never quietly relaxed to declare victory.

## Project memory is part of the job

The human should not have to manage project memory manually. Maintaining `.ratchet/STATE.md` and `.ratchet/DECISIONS.md` is part of normal agent work.

### Memory safety

Treat committed Ratchet memory as repository-visible information.

- Never write secrets, credentials, access tokens, private keys, personal/customer data, or sensitive security/incident details into Ratchet memory. In this repo that includes: the App Store Connect API key and issuer id, Supabase service keys, Netlify tokens, user emails, prod row contents. Refer to them by *where they live* (keychain, Netlify env, the owner's key file) and by opaque ids at most.
- Record only sanitized facts and references. Point to the approved secret manager, incident system, ticket, or other protected source without copying sensitive contents.

### STATE.md

Treat `.ratchet/STATE.md` as the semantic handoff for the current branch/workstream.

- Update it automatically whenever meaningful workstream state changes: a milestone completes, active work changes, a blocker appears or clears, verification status changes, or the next action changes.
- Always leave it current before ending a nontrivial session or handing the branch/workstream to another agent.
- Replace stale state instead of appending a session diary. It is a dashboard, not a transcript.
- Store only context a fresh competent agent cannot safely infer from the repository.
- Do not attempt live cross-branch or cross-clone synchronization. Git is the integration mechanism.
- When integrating branches, reconcile `STATE.md` against the resulting code and tests, then write one clean post-integration state. If incoming state conflicts with repository reality, trust verified repository reality and repair the state.

### DECISIONS.md

Treat `.ratchet/DECISIONS.md` as durable shared project memory. The agent is responsible for deciding when a choice is durable enough to record.

Use this autonomy ladder:

- **Low impact:** routine implementation choices that are obvious from the code. Decide autonomously and do not record them unless their rationale would otherwise be lost.
- **Medium impact:** durable technical or product choices that constrain future work but are reversible and within the task's authorized scope. Decide autonomously, record them in `DECISIONS.md`, and surface them in the completion summary.
- **High impact:** choices with major blast radius or difficult reversal, including architecture replacement, destructive data changes, major dependency/platform changes, public API or shared-contract changes, security-sensitive policy changes, or material product-scope changes. Propose the decision and require explicit human approval before accepting or executing it.

- Append durable decisions; never silently rewrite accepted rationale.
- Parallel branches may add decisions independently. At integration, preserve compatible decisions from both sides. If accepted decisions conflict materially, stop and escalate rather than choosing silently.
- If a decision changes, mark the old entry superseded and append the replacement.
- If repository reality conflicts with an accepted decision, stop and report the conflict instead of choosing one silently.
- Do not preserve chat transcripts as project memory.

## Checkpoint discipline

- One conceptual change per step. Each step ends with the repo in a known-good state.
- Never batch edits across a failing state. Never stack a later step on an unverified earlier one.
- Do the riskiest or most informative step first so a fatal discovery happens early.

## Verification

- Never claim tests pass without running them.
- Reproduce a bug before fixing it whenever reproduction is possible.
- After writing a regression test, prove it can fail by reverting or disabling the fix, confirm failure, restore the fix, and confirm pass.
- Check installed-version APIs rather than relying on memory.
- If a test fails and the cause is not understood, stop and report. Do not hide, bypass, or reshape the test merely to produce green output.
- A check that ran but produced no verdict — flaky, interrupted, blocked part-way — is INCONCLUSIVE. Inconclusive is never a pass and never counts toward "done".
- When two fixes that share one premise have failed the same check, write the premise down and test it directly before a third fix. A guard added because it "might help" is a hypothesis; when evidence refutes it, revert what it motivated.
- The manual's §3 lists the two known pre-existing failures on `main`. Name them when hit; never "fix" them inside an unrelated PR.

## Scope law

- No drive-by changes: no unrelated reformatting, renames, cleanup, or debug output.
- Before summarizing, inspect the full diff and justify every hunk against the request.
- If one behavior change requires touching many files, call out the blast radius and reconsider whether the change is happening at the right layer.

## Hard stops

Require explicit human approval before:

- creating, modifying, or executing any database migration
- irreversible data changes
- force pushes, history rewrites, branch deletion, or destructive git operations
- deleting files or data outside the immediate task
- sending data to external systems
- changing public API surfaces or other shared contracts
- accepting or executing a high-impact decision as defined above
- anything listed as project-specific hard-stop territory below

The guard hooks intentionally enforce some of these categories more conservatively than prose alone. If a guarded action is genuinely approved, the human performs or explicitly bypasses the guard; agents must not invent self-approval mechanisms.

## What enforces these rules

Every rule above is either enforced by something that fires on its own or held by prose alone. This table says which. A **prose only** row is a promotion candidate: when a failure escapes through one, `ratchet-tighten` adds the check in the same change rather than another sentence. Drop a row when its mistake can no longer happen.

| Rule | Enforced by |
|---|---|
| Checks run after the last edit, before "done" | `check-on-stop.sh` stop hook (Claude Code); `ratchet-done` step 2 elsewhere |
| A regression test is seen failing without the fix | `rrr.sh` via `ratchet-bugfix` |
| Lint and typecheck on every edited file | `lint-edited-file.sh` post-edit hook (Claude Code); the check command elsewhere |
| Destructive git, migrations, outbound sends need approval | `guard-destructive.sh` (Claude Code); prose only elsewhere |
| Project memory is current and holds no placeholder | stop hook placeholder check; `ratchet-handoff` |
| Review findings are reproduced before they are acted on | `ratchet-review` step 4 |
| Diff contains only the requested change | prose only (`ratchet-done` step 1) |
| No secrets or transcripts in project memory | prose only (`ratchet-handoff` step 4) |
| Public API and shared-contract changes need approval | prose only |
| High-impact decisions wait for approval | prose only |
| `npm test` runs when `tablet-notes-api/` changed; the iOS build runs when Swift/project files changed | `check-on-stop.sh` stop hook (Claude Code); run by hand elsewhere, per Repo specifics |
| Netlify functions are syntax-checked on every edit | `lint-edited-file.sh` post-edit hook (Claude Code, `node --check`); prose only elsewhere |
| `netlify deploy --prod`, `netlify env:*` changes, Supabase migrations, `xcrun simctl erase`, and any push that would update `main` need the owner | `guard-destructive.sh` TabletNotes section (Claude Code); prose only elsewhere |
| Prod writes with the service key, StoreKit/tier changes, the reset/restore flow in `TabletNotesApp.init` | prose only (manual §11) |

An exception to an enforced rule lives on the offending line with a reason, an expiry date, and the approving human's name, never in a global allowlist.

## Delegation and model tiers

The session that talks to the owner is the **orchestrator**. It cannot switch its own model. This section routes delegated work only when the owner has authorized delegation — it does not itself grant that authority. Delegate only bounded work and own the result: re-run the checks or read the evidence directly; never accept a subagent's "done" on trust. This contract binds every tier equally; a faster model gets a shorter leash, not a looser contract.

Tiers are roles, not vendors. Which model fills each tier lives in the tool's adapter (`CLAUDE.md` for Claude Code, `CODEX.md` for Codex); a tool with no adapter runs single-model under the paragraph below. If a named model is unavailable, use the strongest available model appropriate to the same tier and state the substitution.

If only one model is available, every tier collapses onto it. The "Owns" column still describes the work; nothing is delegated. "Escalate on the second failure" then means stop and report to the owner. Verification, hard stops, and the self-test are unchanged. A single weaker model gets more process, not fewer rules.

| Tier | Owns | Never |
|---|---|---|
| Orchestrate | The conversation with the owner; plans and blast-radius calls; root-cause diagnosis of prod or device symptoms (prod queries, edge logs, phone log capture); anything in hard-stop territory (migrations, entitlements, deploys, the reset/restore flow); cross-cutting changes spanning the sync engine, the recording pipeline and `SermonService`; medium/high-impact `DECISIONS.md` entries; arguing or accepting review findings; the final Ratchet report. | Delegates a decision it should make itself. |
| Operate, high risk | Code in `SermonService.swift`, `Services/Sync/`, `Services/Recording/`, `Services/Notes/`, `Views/MainAppView.swift`, and any Netlify function or `utils/` module that writes prod data; concurrency or actor-isolation changes; test-first bug fixes that must prove reproduce-revert-restore; migration *proposals* (never execution). | Merges, deploys, executes migrations, or edits `.pbxproj` by hand. |
| Operate, routine | Views outside `MainAppView`; components; `utils/` modules with a test suite; well-specified refactors within one file; new tests for described behavior. | Touches the high-risk modules above, resolves merge conflicts, or changes a public API surface or shared contract. |
| Git & docs | Git mechanics with fully specified inputs (create a named branch from fresh `main`, commit a given message from a file, push a feature branch, rebase a conflict-free branch); documentation writing and edits in `docs/`; PR body drafts; `.ratchet/STATE.md` refreshes; Linear comments and issue-link updates; typo and formatting fixes; read-only lookups and greps; running a named check and reporting its output verbatim. | Edits code or project files, resolves conflicts, runs a git operation on the hard-stop list, rewords this file, the manual, or an adapter, writes `DECISIONS.md` entries, or interprets a failing test. |

- **Route by blast radius, not by apparent size.** A one-line change in `SermonService` is high-risk work; a fifty-line new settings row is routine.
- **Escalate on the second failure.** If a routine or git-and-docs task fails verification twice, or turns out to touch a hard stop, return it to the orchestrator or the next tier up with the failure attached. Never retry a weaker model into the same wall.
- **Reviews go up a tier.** A hostile diff review (`docs/ratchet/review-prompts.md` §5) uses a model at least as strong as the one that wrote the diff, in a fresh context. Where the tool allows it, a different model family as reviewer is better still: a finding two families raise independently is the strongest signal.
- **The author's run is not the verdict for high-risk work.** An author checks what it meant to build. For work in the high-risk tier, "done" needs a verdict from a context that did not write the code (`ratchet-review`), on the exact commit being accepted. Green CI and an approving bot are inputs to that verdict, not the verdict.
- **Every delegation is a brief with fixed fields:** goal in one sentence, scope (paths it may and may not write), context pointers, acceptance (the predicate), the verify command, forbidden actions (the hard stops that apply), and the report shape. A field you cannot fill means the unit is not scoped yet; do not delegate it.
- **Verification is tier-independent.** The stop gate, the guard, `test-hooks.sh`, the hard stops, the manual's quality bar, and the self-test apply to every model equally. That is the whole point.
- **When unsure, go up.** Use the high-risk operator tier. The cost of a wrong cheap answer in this repo is a lost recording, not a wasted token.

## Reporting format

Every nontrivial completion summary should contain, in order:

1. **What changed** — the behavior, first.
2. **Shape & why** — files touched, approach chosen, and why if alternatives were live.
3. **Verification** — what was actually run / read / assumed, and what ran but was inconclusive. Never collapse these categories.
4. **Residue** — assumptions, untested paths, follow-ups, and deliberately untouched issues.
5. **Handoff** — confirm `.ratchet/STATE.md` is current for this branch/workstream and call out any new medium-impact decisions recorded or high-impact decisions awaiting approval.

A procedure step that was skipped stays in the report as `skip: <reason>`. A step that silently vanishes is the failure the report exists to catch.

## Repo specifics

Full detail lives in `docs/OPERATING-MANUAL.md`; this is the index.

- **Run everything (iOS):** `xcodebuild build -scheme TabletNotes -destination 'platform=iOS Simulator,id=A476D5E8-216E-481B-ADFE-6EB2E52FBEAC'` (an iOS 18.5-or-newer simulator is required, deployment target is 18.5; run from `TabletNotes/`). The stop hook runs this automatically when Swift files changed.
- **Run tests (iOS):** `xcodebuild test -scheme TabletNotes -destination '<same>' -only-testing:TabletNotesTests/<Suite>` — the suites your change touches, not the whole target. Use the simulator above, not one that has been used for manual recording (orphan audio in its container makes the SermonService suites fail).
- **Run everything (backend):** `cd tablet-notes-api && npm test` (~1 s), plus `node --check` on every changed function. The stop hook runs `npm test` automatically when `tablet-notes-api/` changed.
- **Known untested / high-risk modules:** `SermonService.swift` (recovery, cloud restore, orphan import — 1,600 lines, largest blast radius), `Services/Sync/` (two-phase engine; per-scope acks; push must never starve pull), `Services/Recording/` (deliberately not main-actor; recovery manifest written synchronously after capture starts), `Views/MainAppView.swift` (its init re-runs on every parent re-render — never construct services there), Netlify functions (no test harness of their own; logic must be extracted to `utils/` to be tested).
- **Public API / shared contract surface:** the Netlify function request/response shapes (`create-sermon`, `update-sermon`, `get-sermons`, `delete-sermon`, `verify-purchase`, `transcribe`, `summarize`, jobs), the Supabase prod schema (`tablet-notes-api/schema/` documents it; live DB is truth), the `syncedScopes` acknowledgment contract between server and client, StoreKit product ids `com.tabletnotes.premium.monthly|annual`, the recovery-manifest UserDefaults key `active_recording_manifest`, and the `notes` os_log category. Changing any of these is a high-impact decision.
- **Environment assumptions worth stating:** Netlify prod auto-deploys on merge to `main` (env-var changes still need `netlify deploy --prod`); Supabase migrations are owner-only via the SQL editor; App Store Connect metadata is edited through the API by the owner's key (path in the owner's memory notes, never in the repo); every release after a live version needs `MARKETING_VERSION` bumped in the project before archiving, and Xcode assigns the build number per version string at upload.
- **Additional hard-stop paths or operations (guard-enforced where possible):** any prod write with the Supabase service key (PATCH/POST/DELETE against PostgREST or storage), `netlify deploy --prod`, `netlify env:set`/`env:unset`, `supabase db push` / `supabase migration up`, `xcrun simctl erase`, pushing to `main` directly, merging a PR without the owner's per-PR go-ahead, anything touching money or entitlements (StoreKit flow, tier logic, `verify-purchase`), and the destructive-store-reset / restore-flag flow in `TabletNotesApp.init`.

## Self-test before every "done"

1. Did I run the available checks, or does the change merely read correct? Is any check that ran without a verdict reported as inconclusive rather than as passing?
2. Does the diff contain only the intended change, and can I justify every hunk?
3. What did I assume about environment, versions, or project state, and did I state it?
4. For a bug fix, do I have evidence the regression test can fail without the fix?
5. Did I autonomously maintain branch/workstream state instead of leaving that work to the human?
6. Did I keep sensitive information out of durable project memory?
7. Did I avoid pretending branch-local state is globally synchronized state?
8. Did any migration, external send, shared-state action, irreversible action, or high-impact choice require human approval before execution?
9. Could a fresh agent continue this branch/workstream from `.ratchet/STATE.md` and `.ratchet/DECISIONS.md` without this conversation?

Any "no" means the work is not done yet.
