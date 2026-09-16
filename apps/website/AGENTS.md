# Website working notes

The repository-root [`AGENTS.md`](../../AGENTS.md) is the canonical operating
contract. Read it and the files it names before changing this site; this file
only records facts local to `apps/website`.

## Scope and deployment

- This is the Tablet Notes public Next.js site. Its deployed Vercel project is
  `tablet-app-landingpage`, with `apps/website` as the target Root Directory.
  The currently live deployment still uses repository root (`.`); changing the
  provider configuration, domain, or environment is an external shared-state
  action and needs owner approval.
- Keep `pnpm-lock.yaml` independent in this directory. The repository is not a
  pnpm workspace: do not add a root workspace file or merge this lockfile into
  another project.
- The migration checklist and cutover gates live in
  [`docs/superpowers/plans/2026-09-15-website-monorepo-migration.md`](../../docs/superpowers/plans/2026-09-15-website-monorepo-migration.md).

## Current behavior

- `app/page.tsx` is the live homepage. It sends visitors to the App Store; it
  does not render a signup form or link to the former waitlist.
- `actions/email-signup.ts` and `components/signup-form.tsx` remain in the
  repository for the retained Resend audience, but are dormant from the
  homepage. Do not invoke or test that action unless a task explicitly
  authorizes external email/contact writes.
- `next.config.mjs` skips ESLint during `next build`, but TypeScript errors are
  not suppressed. `tsconfig.json` is strict; run the explicit typecheck in the
  README before relying on a production build.
- `MEMBERS_SETUP.md`, `lib/stripe.ts`, and the pre-launch section components
  are historical material, not authority for the deployed site or current
  signup/payment behavior. The inherited `CLAUDE.md` also contains stale claims
  (including TypeScript suppression and old component paths); this file and the
  current code take precedence for website facts.

## Verification boundary

Run website commands from this directory with the pinned pnpm invocation in
[`README.md`](README.md). Keep development and production-build processes from
sharing `.next` concurrently. Check homepage, privacy, and terms routes and
their `/launch` and `/images` assets when a change can affect rendering.
