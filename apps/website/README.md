# Tablet Notes website

The public Tablet Notes site is a Next.js application. It has its own
`pnpm-lock.yaml`; it is not part of a repository-wide pnpm workspace.

Use Node 22, the version used by the deployed site. Use the pinned pnpm
invocation below for reproducible local and hosted builds:

```bash
npx pnpm@10.15.1 install --frozen-lockfile
npx pnpm@10.15.1 dev
npx pnpm@10.15.1 exec tsc --noEmit
npx pnpm@10.15.1 build
node scripts/check-server-actions.mjs
npx pnpm@10.15.1 start --port 3018
```

Run these commands from `apps/website`. Do not run the development server and
production build at the same time: both use `.next`.

`next build` intentionally skips ESLint, but it does perform TypeScript
validation; the explicit `tsc --noEmit` command is still required verification.

## Smoke test

After starting a local production server, verify the public routes and
representative image/video assets without submitting a form:

```bash
node scripts/smoke-test.mjs
```

The script defaults to `http://localhost:3018`. To test a Vercel Preview or
other hosted deployment, pass its URL or set `BASE_URL`:

```bash
node scripts/smoke-test.mjs https://preview.example.com
BASE_URL=https://preview.example.com node scripts/smoke-test.mjs
```

It checks the homepage, privacy and terms pages, the generated OpenGraph image,
and homepage-referenced representative image and video assets. It makes GET
requests only; it never invokes the dormant Resend signup action.

For protected previews, authenticate with Vercel first. The smoke script accepts
an optional `SMOKE_COOKIE` environment variable for an authorized bypass cookie;
never commit or print its value. Requests have a 30-second timeout and refuse
redirects, so authentication cookies cannot follow a redirect to another host.

After every build, `node scripts/check-server-actions.mjs` verifies that the
Node and Edge action registries are empty. Reintroducing any Server Action
requires an explicit security review before changing this assertion.

The homepage is a download page, not a waitlist: it currently has no reachable
signup form. The dormant Resend action is retained for the existing audience;
never submit it for a smoke test. Historical Stripe/member setup notes are not
current deployment instructions.

Vercel's target configuration is project `tablet-app-landingpage` with this
directory (`apps/website`) as its Root Directory. Production currently runs
from repository root (`.`), so a provider cutover requires owner approval and
the migration gates in
[`docs/superpowers/plans/2026-09-15-website-monorepo-migration.md`](../../docs/superpowers/plans/2026-09-15-website-monorepo-migration.md).
