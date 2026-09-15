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
