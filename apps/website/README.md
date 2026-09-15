# Tablet Notes website

The public Tablet Notes site is a Next.js application. It has its own
`pnpm-lock.yaml`; it is not part of a repository-wide pnpm workspace.

Use Node 22, the version currently used by the deployed site. The source
package does not pin a Node or pnpm version, so use the following reproducible
pnpm invocation rather than treating the source metadata as a version pin:

```bash
npx pnpm@10.15.1 install --frozen-lockfile
npx pnpm@10.15.1 dev
npx pnpm@10.15.1 exec tsc --noEmit
npx pnpm@10.15.1 build
npx pnpm@10.15.1 start --port 3018
```

Run these commands from `apps/website`. Do not run the development server and
production build at the same time: both use `.next`.

`next build` intentionally skips ESLint, but it does perform TypeScript
validation; the explicit `tsc --noEmit` command is still required verification.

The homepage is a download page, not a waitlist: it currently has no reachable
signup form. The dormant Resend action is retained for the existing audience;
never submit it for a smoke test. Historical Stripe/member setup notes are not
current deployment instructions.

Vercel's target configuration is project `tablet-app-landingpage` with this
directory (`apps/website`) as its Root Directory. Production currently runs
from repository root (`.`), so a provider cutover requires owner approval and
the migration gates in
[`docs/superpowers/plans/2026-09-15-website-monorepo-migration.md`](../../docs/superpowers/plans/2026-09-15-website-monorepo-migration.md).
