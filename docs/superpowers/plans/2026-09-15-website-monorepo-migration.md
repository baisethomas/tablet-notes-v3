# Live website monorepo migration — TAB-118

Status: preparation in progress; production cutover requires owner approval.

Issue: https://linear.app/loomlogiclabs/issue/TAB-118/import-live-website-into-monorepo-and-prepare-vercel-cutover

## Outcome and scope

Move the source of the live website into `apps/website` in `baisethomas/tablet-notes-v3`, retaining the existing Vercel website project, domain assignments, and Git history. The first stage imports only the website. Existing `TabletNotes/`, `tablet-notes-api/`, `supabase/`, `support-automation/`, and `Marketing/` paths remain stable. This keeps the website cutover independently verifiable. Wider directory reorganization, Android, shared contracts, package-manager consolidation, billing, and asset cleanup are later work.

Success means the same public routes and assets are served from the approved destination commit, with a verified rollback deployment and working future Git deployments. Import completion alone is not live migration completion.

## Observed baseline (2026-09-15 UTC)

| Item | Observed value |
| --- | --- |
| Destination base | `3a615c518e7ca4376dc23c1ab13f0f98e7fd7362` (TAB-117 merged) |
| Source | `baisethomas/tablet-app-landingpage`, branch `main` |
| Source and live deployment commit | `70d55041cf5874bf079ad0846d7ca8395886f0e9` |
| Original source history | 65 commits; about 58 MiB packed objects |
| Imported source tree | `e18fa1d020672350bb585ca442a6c9f3c174cc3e` |
| Website Vercel project | `tablet-app-landingpage`, team `loomlogiclabs-projects` |
| Current root / target root | `.` / `apps/website` |
| Framework / runtime | Next.js / Node 22.x |
| Current install/build | Framework defaults, no explicit override |
| Production tracking | Source repository `main`; auto-assignment enabled |
| Domain routing | `tabletnotes.io` redirects to `www.tabletnotes.io`; `tabletnotes.vercel.app` also attached |
| Current production deployment | `dpl_5t16UhoBdGGoueM86XnQFy2iE37Q`, READY and promoted |
| Rollback candidate URL | `https://tablet-app-landingpage-aehdu9uw4-loomlogiclabs-projects.vercel.app` |
| Environment names | `EMAIL_PROVIDER_API_KEY` exists for Production, Preview, and Development; values not inspected |
| Ignored Build Step / deploy hooks | No configured ignored command; no Git deploy hooks listed |
| Git merge modes | Merge commits are allowed, alongside squash and rebase |

There is a DIFFERENT Vercel project named `tablet-notes-v3`, whose root is `tablet-notes-api`. Do not select or reconfigure it for the website. Support automation also has its own Vercel project. Authentication alone does not prove all required Git-integration permissions; verify the installation can connect the destination repository before cutover.

The website uses Next 15.2.8, React 18.3.1, a pnpm v9-format lockfile, and no package-manager pin. `next.config.mjs` skips ESLint during builds but DOES NOT skip TypeScript. The current homepage exposes download, anchor, social, privacy, and terms links; the old signup components are not rendered. Resend code remains in the tree and must not be exercised with real email during migration checks. `MEMBERS_SETUP.md` and placeholder Stripe code are historical material, not authority to change entitlement or database contracts.

## Delegation and ownership

All agents follow root `AGENTS.md` and `CODEX.md`; subagents have bounded file ownership.

| Work package | Assigned model | Deliverable / limit |
| --- | --- | --- |
| Plan, integration, issue, approval packet | Root orchestrator | Own scope, Ratchet decisions/state, independent evidence checks, production operations |
| Access inventory and exact Git import | `gpt-5.6-luna` | Read-only account checks; prescribed non-squashed subtree import in isolated worktree |
| Named verification commands | `gpt-5.6-luna` | Run frozen install, typecheck, build; return failure verbatim without fixing it |
| Website docs and verification checklist | `gpt-5.6-terra` | Add website README and scoped AGENTS guidance; preserve imported application behavior |
| Cutover and final review | `gpt-6-astra` | Review deployment risks, rollback, full diff, and source ancestry; no production execution |

Only one operator changes live Vercel configuration. Agent failure escalation follows CODEX.md; unknown build failures stop downstream steps until understood.

## Phase 1 — Isolated import

1. Create the issue branch from fresh `origin/main` in a separate worktree. Existing uncommitted Ratchet and Marketing work stays in the original checkout.
2. Pin the source SHA and use a non-squashed subtree import:

   ```sh
   git subtree add --prefix=apps/website https://github.com/baisethomas/tablet-app-landingpage.git 70d55041cf5874bf079ad0846d7ca8395886f0e9 -m 'chore(web): import website with original history (TAB-118)'
   ```

3. At the import commit, verify source ancestry and an empty source-versus-subdirectory diff. Import commit: `90c27d8645c5fddb0994135081fedaca139c6ac6`.
4. Add only migration documentation and local operating guidance. Preserve the original package and lockfile. No root workspace changes or dependency upgrades.
5. GitHub must integrate this PR with **Create a merge commit**. Squash or rebase merge loses the promised source ancestry. Recheck ancestry on destination `main` afterward. Source GitHub issues, PRs, branch refs, and releases remain in the old repository.

Exit: original tree equality proven, source commit is an ancestor, full diff scoped to imported website and migration documentation.

## Phase 2 — Local verification and review

Run from `apps/website` with Node 22 and Corepack auto-pin disabled. pnpm 10.15.1 is the explicit local test version; the historical Vercel pnpm version is not yet verified.

```sh
npx --yes pnpm@10.15.1 install --frozen-lockfile
npx --yes pnpm@10.15.1 exec tsc --noEmit
npx --yes pnpm@10.15.1 build
npx --yes pnpm@10.15.1 start --port 3018
```

Check `/`, `/privacy`, `/terms`, generated OpenGraph image, linked CSS/JS, and referenced `/launch` media and `/images` assets. Verify page title, canonical metadata, App Store and Instagram targets, anchors, mobile layout, video poster/reduced-motion behavior, and absence of a newly exposed signup form. Do not submit contacts or send email. Stop the local preview after testing.

A failing baseline is compared against the pinned original source under the same runtime and commands. Do not disable checks or upgrade dependencies to hide a failure. `pnpm build` skips ESLint by existing design; do not report it as lint verification. No iOS or backend code changes means their builds are not part of this website-only gate.

Exit: recorded command outcomes and reviewed diff; limitations explicitly listed in PR. Keep production cutover blocked on unresolved build failures.

## Phase 3 — Hosted Preview preparation

Use an isolated validation Vercel project, with no production domains, to test Git checkout from the destination repository and Root Directory `apps/website` without editing the live project's current repo/root pair. Explicitly select the non-production TAB-118 branch and verify deployment environment is Preview; do not deploy `main` as that temporary project's Production deployment. Match Node 22, Next.js, install/build behavior and protection. Explicitly choose Preview variables; never copy Production secrets wholesale. The currently rendered routes can be tested without Resend credentials.

Project creation and upload are an external execution step: record the concrete settings and obtain authorization if not already granted. A local build does not count as a hosted Preview. Validate the same routes and visual checks, plus deployment metadata proving the expected destination commit/root. Do not disable deployment protection to inspect a preview.

Automatic unaffected-project skipping requires workspace configuration. This migration keeps package managers local, so initially tolerate extra website builds. A tested explicit Ignored Build Step can follow separately; a naive one-commit diff is unsafe for merge commits, first builds, and shared files.

## Phase 4 — Owner approval packet

Before execution, provide the reviewed PR and commit, local and hosted verification, exact current/target settings, current rollback candidate, and remaining risks. Approvals cover the specific PR merge, production configuration transition, staged Production build, and promotion. Repository hard stops require owner go-ahead for production changes and merge; planning/delegation is not that go-ahead.

| Setting | Before | After |
| --- | --- | --- |
| Website project | `tablet-app-landingpage` | same project |
| Git repository | `baisethomas/tablet-app-landingpage` | `baisethomas/tablet-notes-v3` |
| Root Directory (project setting) | `.` | `apps/website` |
| Production branch | `main` | `main` |
| Framework / Node | Next.js / 22.x | same |
| Domains and secret values | existing | preserved |
| Auto domain assignment | enabled | disabled during cutover; restore after verification |

Root Directory is a Vercel project setting, not a `rootDirectory` key invented in `vercel.json`. Reconfirm current settings and source HEAD immediately before execution; refresh the import if the live source advanced.

## Phase 5 — Controlled production cutover

1. Establish a short website deployment freeze before the final source comparison and merge. Inventory and drain queued builds and other automation; record the current eligible rollback deployment again. Recheck source HEAD and live deployment SHA against the imported source SHA. If either differs, refresh the import and repeat validation before proceeding.
2. Owner merges the import PR using a merge commit while the live website remains attached to the old repository. Verify original source ancestry on destination `main` and record its new SHA. Inspect existing Netlify/Vercel integrations triggered by the merge; their paths remain unchanged. Keep the website freeze in effect through promotion and verification.
3. Disable auto-assignment of Production domains BEFORE changing Git repository or root. Verify it is disabled. Existing domains continue serving the known-good deployment.
4. Under a single operator, connect the existing website project to the destination repo and set Root Directory `apps/website`. These are separate settings; a build between updates may see a mismatched repo/root, so leave auto-assignment disabled and drain any such builds. Verify the final pair, branch, commands, environment scopes, domain routing, and Git installation access.
5. Create a staged Production deployment from the approved destination commit, with Production environment, without assigning live domains (documented CLI workflow: `vercel --prod --skip-domain`; verify exact CLI help and project link before execution). Never let implicit linking choose the API's similarly named project. Inspect repo/SHA/root/environment metadata and validate its URL and build logs.
6. Promote that exact staged Production deployment only after checks pass. Preview-to-Production promotion can rebuild with different variables; staged Production promotion avoids this artifact mismatch.
7. Verify public apex redirect, `www` TLS, routes, media, metadata and download links. Check deployment errors and domain assignments. Restore intended automatic assignment after verification and confirm future branch tracking.
8. Record live SHA/deployment ID and observed checks in Ratchet state and the issue. Close only when served production behavior and future deployment configuration are verified.

## Rollback

Before cutover, verify the recorded old deployment is retained and eligible under the project's current plan. If staged validation fails, keep live domains on the old deployment and repair or restore the settings. If public checks fail after promotion, use the approved Instant Rollback to the recorded old Production deployment and verify public routes again.

Rollback restores the served artifact, not Git repository/root configuration or external service state. If abandoning migration, separately restore the old repo/root while auto-assignment remains disabled, verify the pair, then explicitly restore intended assignment behavior. Vercel disables auto-assignment following rollback; confirm it rather than assuming it. Preserve the old repository and deployment through stabilization. Archiving the old repo is a separate owner-approved follow-up; no history rewrite or deletion is required.

## Evidence and remaining gates

- Access: Vercel and GitHub authenticated; actual website project and separate API project inspected read-only.
- Import: original tree and source ancestry verified by worker and independently by root.
- Local frozen install, explicit TypeScript check and Next production build passed on Node 22.14.0 / pnpm 10.15.1. Root independently repeated typecheck/build successfully from `apps/website`; 7 static pages generated. Package and lockfile unchanged. Existing build skips ESLint; this is not lint verification. pnpm warned of ignored `sharp` and `unrs-resolver` build scripts; build still passed without enabling them.
- Hosted Preview, staged Production, visual browser checks, production settings changes and live cutover: not performed.
- Root started this worktree's production server on port 3028 and confirmed HTTP 200 with expected content types for `/`, `/privacy`, `/terms`, `/opengraph-image`, `/launch/icon.png`, and the brand WebM/MP4. Server stopped afterward. A worker's separate port-3018 checks used an existing server and are excluded from this build's evidence.
- No email tests or changes to backend, database, billing, or existing client paths are authorized by this plan.

## References

- [Vercel promotion and environment behavior](https://vercel.com/docs/deployments/promoting-a-deployment)
- [Vercel monorepo project configuration and build skipping](https://vercel.com/docs/monorepos)
- [Vercel Instant Rollback](https://vercel.com/docs/instant-rollback)
- [Vercel staged CLI deployment](https://vercel.com/docs/cli/deploying-from-cli)
