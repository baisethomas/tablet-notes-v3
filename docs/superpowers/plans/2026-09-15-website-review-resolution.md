# TAB-118 review resolution

## Dependency audit

The imported source was preserved at commit `90c27d8`. Review remediation follows in separate commits: Next.js and eslint-config-next are aligned at 15.5.24; Resend is pinned at 6.14.0 to remove the vulnerable legacy svix/uuid chain. Seventeen range-scoped transitive overrides select patched releases within their existing major lines. pnpm is pinned at 10.15.1 for reproducible installation.

On 2026-09-15, `pnpm audit --json` reported zero critical, high, moderate, low and informational vulnerabilities after remediation. This is evidence of the dependency audit result, not a claim that the application is immune to every security issue. The source website's Production deployment is unchanged until the approved cutover.

## Email action reachability

Both the imported and patched production builds have empty `node` and `edge` registries in `.next/server/server-reference-manifest.json`. The homepage does not import the old signup component. The assertion that the legacy email action is currently callable is not supported by these builds. No email or contact writes were performed to test it.

`node scripts/check-server-actions.mjs` now enforces zero public Server Actions after build. A future change that reconnects the signup UI must intentionally revise this guard after reviewing authentication/abuse protection. The action was retained to preserve source behavior; source presence alone is not deployment reachability.

## Repeatable checks and metadata cleanup

`node scripts/smoke-test.mjs <base-url>` checks homepage/legal content, links, generated OpenGraph, and representative image/video responses. It uses GET only, bounds requests at 30 seconds, and rejects redirects. An optional authorized cookie is accepted through the environment for protected Preview checks.

The imported `.DS_Store` was removed in the remediation diff and is ignored. It remains recoverable in the source/import Git history.

## Monorepo build behavior

`outputFileTracingRoot` explicitly selects the website directory. This prevents Next from inferring the repository root from the unrelated root package-lock. Website dependencies remain independent; no backend, native, schema or billing changes are included.

## Handoff

See the migration plan and PR #82 for the final hosted Preview URL and verification evidence. Review remediation extends the original byte-identical import; ancestry preservation still requires a merge commit. Production merge and cutover remain separate owner-reviewed steps.
