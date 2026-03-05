# CI/CD Pipeline in Cal.com

## Overview

Cal.com uses a multi-layered CI/CD pipeline built on GitHub Actions with Turborepo for build optimization and Docker for containerization. The pipeline is designed for a Yarn 4 monorepo with multiple deployable applications and packages. CI runs on Blacksmith runners (faster GitHub-sponsored runners) and includes extensive caching strategies to minimize build times.

**Key characteristics:**
- **Monorepo structure:** Multiple apps (web, api/v1, api/v2) and packages (trpc, features, ui, app-store, etc.)
- **Build system:** Turborepo with remote caching via TURBO_TOKEN/TURBO_TEAM
- **Test suites:** Unit tests (Vitest), integration tests (Vitest + integration mode), E2E tests (Playwright)
- **Security:** Trust-check gate on PRs to prevent untrusted contributor code execution
- **Deployment:** Docker-based (multi-stage builds, multi-architecture support)
- **Database:** PostgreSQL 18 with seeded snapshot caching for E2E tests

---

## PR Workflow (pr.yml)

**Triggers:** Pull requests to main/gh-actions-test-branch, workflow_dispatch

### Security Gate: Trust Check
Before any job executes PR code, a trust check runs to verify:
1. Author is a trusted contributor (OWNER, MEMBER, COLLABORATOR association)
2. OR author has write access via API check
3. OR external contributor has 'run-ci' label added by someone with write access (with staleness validation)

### Path Filtering
Uses `dorny/paths-filter@v3` to conditionally skip expensive jobs:
- **Files requiring all checks:** Everything except `.vscode/`, docs, i18n common.json, CODEOWNERS
- **API v2 changes:** Changes in `apps/api/v2/`, `packages/platform-*`, `packages/trpc`, `docs/api-reference/v2`, or Prisma schema
- **Prisma changes:** Changes in schema or migrations

### Conditional Job Execution
- **Type-check, lint, unit-test, security-audit:** Always run if files require all checks
- **E2E tests & builds:** Only run if PR has `ready-for-e2e` label AND files require all checks
- **Prisma migration check:** Only runs if Prisma schema or migrations changed

### DB Cache Strategy
- On PR, the `prepare` job checks if a DB cache exists for the current migrations/schema hash
- If cache hit, skip setup-db and re-use seeded database backup
- If cache miss, `setup-db` seeds a fresh DB and exports PostgreSQL dump via `pg_dump`

---

## Core Check Workflows

### check-types.yml
- **Runner:** blacksmith-4vcpu-ubuntu-2404
- **Heap:** NODE_OPTIONS=--max-old-space-size=12288 (12GB needed for full monorepo)
- **Command:** `yarn type-check:ci` (depends on `@calcom/trpc#build`)

### lint.yml
- **Runner:** blacksmith-2vcpu-ubuntu-2404
- **Command:** `yarn lint` (uses Biome, not ESLint)

### unit-tests.yml
- **Runner:** blacksmith-4vcpu-ubuntu-2404, timeout 20min
- **Commands:**
  - `yarn prisma generate`
  - `yarn test -- --no-isolate` (all unit tests)
  - `TZ=America/Los_Angeles VITEST_MODE=timezone yarn test -- --no-isolate` (timezone-specific)
- **VITEST_MODE values:** `default`, `integration`, `timezone`

### api-v2-unit-tests.yml
- Separate from main unit tests, uses Jest in `apps/api/v2`
- Requires `yarn workspace @calcom/platform-libraries build` first

### check-prisma-migrations.yml
- Validates migrations match schema via `npx prisma migrate diff --exit-code`
- Uses PostgreSQL 18 service container

### security-audit.yml
- Runs `yarn audit` for dependency security checks

---

## E2E Test Workflows

All E2E workflows use sharding (matrix strategy) to parallelize tests.

| Workflow | Shards | Services | Notes |
|----------|--------|----------|-------|
| `e2e.yml` | 8 | postgres:18, mailhog | Main Playwright E2E, 4 workers per shard |
| `e2e-api-v2.yml` | 4 | postgres:18, redis | Jest E2E, 29GB heap |
| `e2e-app-store.yml` | - | postgres:18, mailhog | App store integration tests |
| `e2e-embed.yml` | - | postgres:18 | Embed library tests |
| `integration-tests.yml` | - | postgres:18, mailhog | Vitest integration mode |

---

## Production Build Workflows

### production-build-without-database.yml (Web)
- Smart cache lookup with branch-scoped keys
- Caches: `.next/`, `public/embed/`, `.turbo/`, `dist/`
- Cache key hashes: yarn.lock + all `.ts/.tsx/.json/.css` + Prisma schema/migrations

### api-v1-production-build.yml
- `yarn turbo run build --filter=@calcom/api...`

### api-v2-production-build.yml
- `yarn workspace @calcom/api-v2 run generate-schemas` then `yarn turbo run build --filter=@calcom/api-v2`

### atoms-production-build.yml
- Builds Atoms UI library (NPM package)

---

## Docker

### Local Development (docker-compose.yml)
- **PostgreSQL 18** - Main database
- **Redis** - Caching
- **Cal.com Web** - Next.js app (from Dockerfile)
- **Cal.com API v2** - NestJS app (from apps/api/v2/Dockerfile)
- **Prisma Studio** (optional) - localhost:5555

### Production Dockerfile (Multi-stage)
1. **builder** - Node 20, yarn install, build @calcom/trpc and @calcom/web with Turbo prune
2. **builder-two** - Copy artifacts, prepare runtime, URL placeholder replacement
3. **runner** - Lightweight Node 20, health checks (wget http://localhost:3000), runs `/calcom/scripts/start.sh`

### release-docker.yaml
- Triggers on git tags (v*) or manual dispatch
- Multi-architecture: AMD64 + ARM64
- Slack notifications on success/failure

---

## Turborepo Integration

### Build Graph
- Root: `"build": { "dependsOn": ["^build"] }` — each package depends on its dependencies' builds
- Web: `"@calcom/web#build": { "dependsOn": ["^build", "copy-app-store-static"], "outputs": [".next/**"] }`

### Cache Invalidation
- `yarn.lock` globally invalidates all caches (`globalDependencies`)
- Per-task inputs specified (source files, config, migrations)
- 314 global environment variables tracked

### Tasks That Never Cache
- `@calcom/prisma#build`, `db-migrate`, `db-seed`, `db-up`, `db-reset`
- `dev`, `dx`, `start`
- `lint:fix`, `type-check:ci`

### Remote Caching (CI)
- TURBO_TOKEN + TURBO_TEAM secrets enable Vercel's Turborepo cloud cache
- Shared across CI runs/machines but branch-scoped

---

## Custom GitHub Actions

| Action | Purpose |
|--------|---------|
| `cache-checkout` | Cache entire git checkout (except node_modules, large assets) |
| `yarn-install` | Three-level cache: yarn download, node_modules, install state |
| `cache-build` | Cache `.next/`, `public/embed/`, `.turbo/`, `dist/` |
| `cache-build-key` | Generate hash from yarn.lock + all source files + Prisma |
| `cache-db` | Cache seeded PostgreSQL via `pg_dump`/`pg_restore` |
| `yarn-playwright-install` | Cache Playwright browser binaries |

---

## Common CI Failure Patterns

### 1. Type-Check OOM
- **Error:** `JavaScript heap out of memory`
- **Fix:** Already handled with `--max-old-space-size=12288`. For local: use 8192.

### 2. Prisma Migration Drift
- **Error:** `prisma migrate diff` non-zero exit
- **Fix:** Run `yarn prisma migrate dev` locally. Verify migration naming: `YYYYMMDDHHMMSS_description.sql`

### 3. Database Cache Invalidation
- **Error:** E2E constraint violations from stale seed data
- **Fix:** Automatic — cache key includes schema/migrations/seed hashes

### 4. Yarn Lock Conflicts
- **Fix:** Always use `yarn` (never npm/pnpm). Use `yarn add package@version`.

### 5. Turborepo Cache Miss
- **Fix:** Verify TURBO_TOKEN/TURBO_TEAM in GitHub secrets. First run on new branch is always slower.

### 6. E2E Timeout / Flakiness
- **Fix:** Tests sharded across 8 workers. Check `--workers=4`. Verify services health.

### 7. Docker Build Fails
- **Fix:** Verify all required ARGs. Check Node version (20). Clear builder cache.

### 8. API v2 Schema Generation Fails
- **Fix:** Check Prisma schema validity. Rebuild: `yarn workspace @calcom/platform-libraries build`

### 9. Secrets Not Available
- **Fix:** Check GitHub Settings > Secrets. Verify `secrets.CI_*` vs `vars.CI_*` references.

### 10. Blacksmith Runner Timeouts
- **Fix:** High-memory tasks need `blacksmith-4vcpu-ubuntu-2404`.

---

## Key Files Reference

| File | Purpose |
|------|---------|
| `.github/workflows/pr.yml` | Main PR CI pipeline |
| `.github/workflows/all-checks.yml` | Merge queue gate tests |
| `.github/workflows/check-types.yml` | TypeScript type checking |
| `.github/workflows/lint.yml` | Biome linting |
| `.github/workflows/unit-tests.yml` | Vitest unit + timezone tests |
| `.github/workflows/api-v2-unit-tests.yml` | API v2 Jest tests |
| `.github/workflows/integration-tests.yml` | Vitest integration mode |
| `.github/workflows/e2e.yml` | Main E2E (Playwright, 8 shards) |
| `.github/workflows/e2e-api-v2.yml` | API v2 E2E (Jest, 4 shards) |
| `.github/workflows/setup-db.yml` | Database seeding + caching |
| `.github/workflows/production-build-without-database.yml` | Web app build |
| `.github/workflows/release-docker.yaml` | Multi-arch Docker release |
| `.github/actions/yarn-install/action.yml` | Smart yarn caching |
| `.github/actions/cache-build/action.yml` | Build artifact caching |
| `.github/actions/cache-db/action.yml` | Database seeding + backup |
| `turbo.json` | Build task definitions + caching rules |
| `Dockerfile` | Multi-stage production image |
| `apps/api/v2/Dockerfile` | NestJS API image |
| `docker-compose.yml` | Local dev stack |
