# Brief: Support routing — Granted AI inbox to LOO / Granted AI, both products isolated

**Project:** tablet-notes-v3 (support-automation)
**Created:** 2026-11-04
**Status:** open

## Task

Linear issue: [TAB-126](https://linear.app/loomlogiclabs/issue/TAB-126/support-automation-route-granted-ai-help-scout-inbox-to-loo-granted-ai)

Linear team GRA was folded into LOO (project "Granted AI") and retired today, but Help Scout mailbox 371514 (Granted AI Support) still routes to the GRA team ID `ec3442ea-feb0-42a3-a355-bdb373c9bc0c`. Update route 371514 to `linearTeamId` `60112c28-9f70-4fc3-9e06-d5963b476947` (LOO) plus `linearProjectId` `fea7755f-3b05-4822-aaad-f298550d3a1c` (Granted AI) in `support-automation/.env.example` (line 9), the README if it shows the GRA ID (currently it does not; lines 27-28 only document `linearProjectId` as optional), and `src/__tests__/supportInboxRouting.test.js` (lines 22 and 37). Confirm `linearProjectId` reaches issue creation (today: parsed at `src/supportInboxRouting.js:40`, passed as `projectId` at `src/supportAutomation.js:296`, set on the Linear input at `src/supportAutomation.js:157-158`); if any link is missing, add it plus a test. Grep the whole repo for any other `ec3442ea` or GRA-key routing (fixture strings like `GRA-1` / `GRA-101` in `supportWebhookHandler.test.js:93,107` and `supportAutomation.test.js:234` are mock identifiers; update them to LOO-style only if they imply routing).

Also make sure both products stay on separate support boxes: Tablet Notes mailbox 360464 routes only to team TAB (`38abf509-9400-4268-a35d-cb64cc6db607`, no project set today), Granted AI mailbox 371514 routes only to LOO + Granted AI project, each with its own test; add a negative test that a Tablet Notes ticket never lands in LOO/Granted AI and a Granted AI ticket never lands in TAB; and confirm unknown mailboxes are ignored rather than falling back to either product (current code: `resolveInboxRoute` at `src/supportAutomation.js:508-519` returns null and the run is ignored at lines 237-241 — no default route found; lock this in with a test). Replies/notes are written back onto the originating Help Scout conversation, with the identity guard at `src/supportAutomation.js:271-285` swapping the other product's name/mailbox/email/signature; add a test that each product's draft uses its own `supportEmail` and `supportSignature`. No cross-routing bug was found on reading; if you find one, fix it in scope and note it in the PR.

Out of scope:
- other routes beyond 360464 and 371514; the TAB route's IDs are unchanged (tests only)
- any other refactor

Linear rule:
- Linear (workspace loomlogiclabs, team TAB) is the source of truth.
- Claim the issue before starting: assign or comment, and move it to In Progress.
- The branch and PR include the TAB issue ID.
- New bugs and follow-ups become linked Linear issues before the session ends.
- The builder moves the issue to In Review, only the verifier's outcome moves it to Verified (via Master Chief), and only Baise moves it to Done.

## Complete means

- [ ] The PR leaves no GRA team ID anywhere in support-automation (`rg ec3442ea support-automation` returns nothing).
- [ ] The routing test asserts LOO team ID `60112c28-9f70-4fc3-9e06-d5963b476947` and Granted AI project ID `fea7755f-3b05-4822-aaad-f298550d3a1c` for mailbox 371514.
- [ ] A routing test asserts mailbox 360464 resolves to TAB `38abf509-9400-4268-a35d-cb64cc6db607` and to no Granted AI project.
- [ ] A negative test shows a 360464 ticket's issue payload never has the LOO team / Granted AI project, and a 371514 ticket's payload never has the TAB team.
- [ ] A test shows an unknown mailbox ID is ignored (no Linear issue, no note) rather than falling back to either product.
- [ ] A test shows each product's draft reply uses its own supportEmail/supportSignature.
- [ ] Tests pass locally and in CI: `cd support-automation && npm test` (runs `node --test src/__tests__/*.test.js`).
- [ ] A unit path that builds the issue payload for 371514 shows `teamId` = LOO and `projectId` = Granted AI.

## Evidence required

- PR link, head SHA, `npm test` output, and CI run link
- the `rg ec3442ea` output (empty) from the PR head
- the payload assertions (371514 → LOO + projectId; 360464 → TAB; negative and unknown-mailbox tests)

## Reserved for the operator

- merge
- deploy
- updating the live `SUPPORT_INBOX_ROUTES` env var in the deployed (Vercel) environment; the new value for route 371514 is:
  `"371514":{"productName":"Granted AI","mailboxName":"Granted AI Support","supportEmail":"support@grantedai.app","supportSignature":"Granted AI Support","agentGuidance":"Use only details present in the ticket. Do not assume iOS, App Store, recording, or Tablet Notes workflows.","linearTeamId":"60112c28-9f70-4fc3-9e06-d5963b476947","linearProjectId":"fea7755f-3b05-4822-aaad-f298550d3a1c"}`
  (route 360464 unchanged)

## Original intake

> Go ahead and fix that support automation
> Make sure both Tablet Notes and Granted Ai are routing to their separate support boxes

## Notes from the CoS

GRA was folded into LOO as project "Granted AI" today (2026-11-04); until this ships, Granted AI tickets target a retired team. Old GRA-xx → LOO-109..185 map: desk/exports/linear-GRA-2026-11-04-map.md. Baise approved this as an exception to one-open-brief-per-project (brief PR #89 is open).
