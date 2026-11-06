# CODEX.md — Codex Adapter
<!-- ratchet-version: 1.3.1 -->

<!--
AGENTS.md is the canonical model-agnostic operating contract (Ratchet). This file only adds
Codex specifics. Do not duplicate universal rules here; if this file and AGENTS.md ever disagree,
AGENTS.md wins and the conflict is a configuration error to report.
Codex auto-loads AGENTS.md, not this file: keep the "Tool adapters" line in AGENTS.md so it is read.
-->

Codex loads `AGENTS.md` automatically for work in this repository; its read order and its
tool-adapter line point here. This file is the Codex-specific adapter, not a second operating
contract.

## Codex specifics

- Claude Code's `.claude/settings.json` hooks are not automatically installed around Codex tool
  calls. Treat the hard stops in `AGENTS.md` as policy even when no guard intercepts a command, and
  run the manual's required verification explicitly rather than assuming a stop hook ran it.
- Codex task context and any harness-managed memory are not model-agnostic project memory. Durable,
  shareable state belongs in `.ratchet/` under the rules in `AGENTS.md`; sensitive private pointers
  do not.
- Codex discovers repo skills in `.agents/skills/`, not `.claude/skills/`. This repo keeps its
  skills (`ship-linear-issue`, `sim-verify`, `deploy-api`) under `.claude/skills/` and Ratchet's own
  skills come from the Claude Code plugin, so Codex will not load either on its own: read the
  matching `SKILL.md` directly when the task matches, and report the gap.
- When a skill step needs something Codex does not have — a hook, the Agent tool's `model` or
  `effort` parameter, a Claude-only command — do not stop, ask, or retry. Do the step's intent by
  hand where you can (run the check yourself, read the skill directly), put one line in the reply,
  `Skipped in Codex: <step>. <reason>.`, and go on. If a later step needs what the skipped step
  would have produced, leave a named placeholder and say so in that line.
- Treat any conflict between this file and `AGENTS.md` as a configuration error. `AGENTS.md` wins;
  report the conflict.

## Model routing

Tiers, what each owns, and the routing rules are defined in `AGENTS.md` → Delegation and model
tiers. This table only says which model fills each tier here (D-20260915-0625 in
`.ratchet/DECISIONS.md`). The orchestrator's model is selected by the Codex host or the owner; it
cannot switch itself to the model named below. The table routes subagents only when the user or
another applicable instruction has expressly authorized delegation — it does not itself grant that
authority.

| Tier | Model |
|---|---|
| Orchestrate | **Host-selected; prefer gpt-6-astra** |
| Operate, high risk | **gpt-6-astra** |
| Operate, routine | **gpt-5.6-terra** |
| Git & docs | **gpt-5.6-luna** |

Model availability varies by Codex host. Use only identifiers the host exposes as available to this
session; a public announcement does not establish access. Use the named model when available;
otherwise use the strongest available model appropriate to the same tier and state the
substitution, as `AGENTS.md` requires. Report a mismatch between the preferred and active
orchestrator model without claiming to change it. When unsure, use `gpt-6-astra`: the cost of a
wrong cheap answer in this repo is a lost recording, not a wasted token.
