# CODEX.md — Codex Adapter

<!--
AGENTS.md is the canonical model-agnostic operating contract (Ratchet). This file only adds
Codex specifics. Do not duplicate universal rules here; if this file and AGENTS.md ever disagree,
AGENTS.md wins and the conflict is a configuration error to report.
-->

Codex loads `AGENTS.md` automatically for work in this repository; its read order points here after
the operating manual. This file is the Codex-specific adapter, not a second operating contract.

## Codex specifics

- Claude Code's `.claude/settings.json` hooks are not automatically installed around Codex tool
  calls. Treat the hard stops in `AGENTS.md` as policy even when no guard intercepts a command, and
  run the manual's required verification explicitly rather than assuming a stop hook ran it.
- Codex task context and any harness-managed memory are not model-agnostic project memory. Durable,
  shareable state belongs in `.ratchet/`; sensitive private pointers do not.
- Use the repo skills in `.claude/skills/` when their workflow matches the task. Their directory name
  is historical, not an instruction to ignore them outside Claude Code.

## Model routing

The session that talks to the owner is the **orchestrator**. Its model is selected by the host or
owner; it cannot switch itself to the model named below. The table routes subagents only when the
user or another applicable instruction has expressly authorized delegation—it does not itself grant
that authority. Delegate only bounded work and own the result: re-run checks or read the evidence
directly; never accept a subagent's "done" on trust. `AGENTS.md` and the manual bind every tier
equally; a faster model gets a shorter leash, not a looser contract.

Model availability varies by Codex host. Use the named model when available; otherwise use the
strongest available model appropriate to the same tier and state the substitution.

| Tier | Model | Owns | Never |
|---|---|---|---|
| Orchestrate | **Host-selected; prefer gpt-6-astra** | The conversation with the owner; plans and blast-radius calls; root-cause diagnosis of prod or device symptoms; anything in hard-stop territory; cross-cutting changes spanning the sync engine, recording pipeline, and `SermonService`; medium/high-impact `DECISIONS.md` entries; arguing or accepting review findings; the final Ratchet report. | Delegates a decision it should make itself. |
| Implement, high risk | **gpt-6-astra** | Code in `SermonService.swift`, `Services/Sync/`, `Services/Recording/`, `Services/Notes/`, `Views/MainAppView.swift`, and any Netlify function or `utils/` module that writes prod data; concurrency or actor-isolation changes; test-first bug fixes that must prove reproduce-revert-restore; migration proposals (never execution). | Merges, deploys, executes migrations, or edits `.pbxproj` by hand. |
| Implement, routine | **gpt-5.6-terra** | Views outside `MainAppView`; components; `utils/` modules with a test suite; well-specified refactors within one file; new tests for described behavior; PR body drafts; `docs/OPERATING-MANUAL.md` or `AGENTS.md` wording changes. | Touches the high-risk modules above, resolves merge conflicts, or changes a shared contract. |
| Chores | **gpt-5.6-luna** | Git mechanics with fully specified inputs; `.ratchet/STATE.md` refreshes; Linear comments and issue-link updates; typo and formatting fixes in docs; read-only lookups and greps; running a named check and reporting its output verbatim. | Edits code or project files, resolves conflicts, writes `DECISIONS.md` entries, or interprets a failing test. |

Rules of thumb:

- **Route by blast radius, not by apparent size.** A one-line change in `SermonService` is high-risk
  work; a fifty-line new settings row is routine implementation.
- **Escalate on the second failure.** If a routine or chores task fails verification twice, or turns
  out to touch a hard stop, return it to the orchestrator or the next tier up with the failure
  attached. Never retry a weaker model into the same wall.
- **Reviews go up a tier.** A hostile diff review (see `docs/ratchet/review-prompts.md` §5) uses a
  model at least as strong as the one that wrote the diff, in a fresh context.
- **Verification is tier-independent.** Repository checks, guards, and the manual's quality bar apply
  to every model equally.
- **When unsure, use `gpt-6-astra`.** The cost of a wrong cheap answer in this repo is a lost
  recording, not a wasted token.
