# Loom & Logic Support Automation

Standalone Vercel Function for shared Help Scout support automation.

## Workflow

1. Help Scout sends a signed conversation webhook to `/api/support-webhook`.
2. The function selects an inbox profile by immutable Help Scout mailbox ID.
3. The support agent triages the request and creates a Help Scout draft reply.
4. Bugs and feature requests are routed to the configured Linear team.
5. Unknown inboxes fail closed without creating drafts, notes, or issues.

## Local verification

```bash
npm install
npm test
```

Environment variables are documented in `.env.example`. Secrets belong in
Vercel environment variables and must not be committed.
