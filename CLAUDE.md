# CLAUDE.md — Claude Code Adapter

<!--
AGENTS.md is the canonical model-agnostic operating contract (Ratchet). This file only adds
Claude Code specifics. Do not duplicate universal rules here; if this file and AGENTS.md ever
disagree, AGENTS.md wins and the conflict is a configuration error to report.
-->

The two files below are imported so Claude Code loads them automatically every session. Any other agent reads them by path.

@AGENTS.md

@docs/OPERATING-MANUAL.md

## Claude Code specifics

- Use plan mode for nontrivial work when available.
- Respect the configured `.claude/hooks/` and never bypass a failing stop/check hook merely to complete the task. The destructive-command guard has no override token by design: when it blocks something the owner genuinely wants, the owner runs it with `! <command>` or disables the hook.
- The guard matches literal command text after stripping quotes, so it over-matches by design. Known false positives: a `$` right after `;`/`&&`, an env assignment with a `$` variable at a command position (use `export` first or a literal path), `bash -c` with variables, and heredoc *prose* that mentions a destructive command next to a `$`. Write prose with the Write tool, keep shell simple, and never disable the hook to get past it.
- Maintain `.ratchet/STATE.md` and `.ratchet/DECISIONS.md` autonomously per the impact ladder in `AGENTS.md`.
- Claude Code's auto-memory (the `MEMORY.md` under `~/.claude/projects/…`) is **per-machine, per-user, and not model-agnostic**. It may hold the owner's private pointers (key locations, account ids, prod row ids). Durable, shareable project state belongs in `.ratchet/`; keep the two from drifting by reconciling `.ratchet/STATE.md` whenever auto-memory changes something another agent would need.
- Repo skills in `.claude/skills/`: `ship-linear-issue` (the one-issue-one-branch-one-PR loop), `sim-verify` (simulator forensics), `deploy-api` (Netlify deploy + verification). Prefer them over ad-hoc procedures.
- The owner reviews on GitHub with Ternary (automated) plus their own eyes. Merges happen only on the owner's explicit per-PR say-so, even when the owner delegates the click to Claude.

## Model routing

The session that talks to the owner is the **orchestrator** and runs on **Fable**. It delegates bounded work to subagents through the Agent tool's `model` parameter and owns the result: it re-runs the checks or reads the evidence itself, never accepting a subagent's "done" on trust. `AGENTS.md` and the manual bind every tier equally; a cheaper model gets a shorter leash, not a looser contract.

| Tier | Model | Owns | Never |
|---|---|---|---|
| Orchestrate | **Fable** | The conversation with the owner; plans and blast-radius calls; root-cause diagnosis of prod or device symptoms (prod queries, edge logs, phone log capture); anything in hard-stop territory (migrations, entitlements, deploys, the reset/restore flow); cross-cutting changes spanning the sync engine, recording pipeline and `SermonService`; medium/high-impact `DECISIONS.md` entries; arguing or accepting review findings; the final Ratchet report. | Delegates a decision it should make itself. |
| Implement, high risk | **Opus** | Code in `SermonService.swift`, `Services/Sync/`, `Services/Recording/`, `Services/Notes/`, `Views/MainAppView.swift`, and any Netlify function or `utils/` module that writes prod data; concurrency or actor-isolation changes; test-first bug fixes that must prove reproduce-revert-restore; migration *proposals* (never execution). | Merges, deploys, executes migrations, or edits `.pbxproj` by hand. |
| Implement, routine | **Sonnet** | Views outside `MainAppView`; components; `utils/` modules with a test suite; well-specified refactors within one file; new tests for described behavior; PR body drafts; `docs/OPERATING-MANUAL.md` or `AGENTS.md` wording changes. | Touches the high-risk modules above, resolves merge conflicts, or changes a shared contract. |
| Chores | **Haiku** | Git mechanics with fully specified inputs (create a named branch from fresh `main`, commit a given message from a file, push a feature branch, rebase a conflict-free branch); `.ratchet/STATE.md` refreshes; Linear comments and issue-link updates; typo and formatting fixes in docs; read-only lookups and greps; running a named check and reporting its output verbatim. | Edits code or project files, resolves conflicts, writes `DECISIONS.md` entries, or interprets a failing test. |

Rules of thumb:

- **Route by blast radius, not by apparent size.** A one-line change in `SermonService` is Opus work; a fifty-line new settings row is Sonnet work.
- **Escalate on the second failure.** If a Sonnet or Haiku task fails verification twice, or turns out to touch a hard stop, it comes back to the orchestrator or goes to the next tier up with the failure attached. Never retry a weaker model into the same wall.
- **Reviews go up a tier.** A hostile diff review (see `docs/ratchet/review-prompts.md` §5) runs on a model at least as strong as the one that wrote the diff, in a fresh context.
- **Verification is tier-independent.** The stop gate, the guard, `test-hooks.sh`, and the manual's quality bar apply to every model the same way. That is the whole point.
- **When unsure, use Fable.** The cost of a wrong cheap answer in this repo is a lost recording, not a wasted token.
