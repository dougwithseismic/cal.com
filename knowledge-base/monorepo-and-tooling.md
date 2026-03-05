# Monorepo and Tooling

> How the Cal.com monorepo is structured, managed, and built with Yarn 4, Turborepo, and Biome.

## Overview

Cal.com is a Yarn 4 (Berry) monorepo managed by Turborepo. It contains two main apps (web, api), 20+ packages, and 70+ app-store integrations. Biome handles linting and formatting (not ESLint). Docker Compose provides local Postgres and Redis.

## Key Locations

| Path | Purpose |
|------|---------|
| `package.json` | Root workspace definition and scripts |
| `turbo.json` | Turborepo pipeline configuration |
| `biome.json` | Biome linting/formatting config |
| `yarn.lock` | Yarn lockfile |
| `docker-compose.yml` | Local dev infrastructure (Postgres, Redis) |
| `Dockerfile` | Production Docker build |
| `.env.example` | Main env template |
| `.env.appStore.example` | App store env template |
| `apps/web/` | Main Next.js application |
| `apps/api/v1/` | REST API v1 (Next.js routes) |
| `apps/api/v2/` | Platform API v2 (NestJS) |
| `packages/` | Shared packages |

## Patterns

### Workspace Structure
**Where:** `package.json:5-16`
**How it works:** Yarn workspaces are defined at root level.
**Example:**
```json
// package.json:5-16
"workspaces": [
  "apps/*",
  "apps/api/*",
  "packages/*",
  "packages/embeds/*",
  "packages/features/*",
  "packages/app-store",
  "packages/app-store/*",
  "packages/platform/*",
  "packages/platform/examples/base",
  "example-apps/*"
]
```

### Key Packages

| Package | Path | Purpose |
|---------|------|---------|
| `@calcom/web` | `apps/web` | Main Next.js app |
| `@calcom/prisma` | `packages/prisma` | Database schema, migrations |
| `@calcom/trpc` | `packages/trpc` | tRPC routers and client |
| `@calcom/features` | `packages/features` | Business logic by domain |
| `@calcom/ui` | `packages/ui` | Shared UI components |
| `@calcom/lib` | `packages/lib` | Shared utilities |
| `@calcom/app-store` | `packages/app-store` | Third-party integrations |
| `@calcom/emails` | `packages/emails` | Email templates |
| `@calcom/embeds` | `packages/embeds` | Embeddable widgets |
| `@calcom/i18n` | `packages/i18n` | Internationalization |
| `@calcom/ee` | `packages/ee` | Enterprise features |
| `@calcom/platform` | `packages/platform` | Platform SDK |

### Key Scripts
**Where:** `package.json`
**Example:**
```bash
# Development
yarn dev              # Start web dev server
yarn dx               # Quick start: Docker + migrations + seed + dev
yarn dev:api          # Web + API proxy + API server

# Building
yarn build            # Build web and dependencies

# Database
yarn prisma migrate dev    # Create migration
yarn prisma db push        # Push schema changes
yarn db-seed               # Seed database
yarn db-studio             # Prisma Studio GUI

# Testing
yarn test             # Run all unit tests (TZ=UTC)
yarn tdd              # Watch mode
yarn e2e              # Playwright E2E
yarn test-e2e         # Seed + E2E

# Code Quality
yarn lint             # Run Biome linting
yarn lint:fix         # Auto-fix lint issues
yarn format           # Format with Biome
yarn type-check       # TypeScript type checking

# App Store
yarn create-app       # Create new integration
yarn edit-app         # Edit integration
yarn delete-app       # Delete integration

# Workspace-specific
yarn workspace @calcom/web <command>
yarn workspace @calcom/prisma <command>
```

### Turborepo Pipeline
**Where:** `turbo.json`
**How it works:** Defines task dependencies, caching, and environment variable passthrough. Global env vars are listed extensively.
**Example:**
```json
// turbo.json:1-4
{
  "$schema": "https://turborepo.org/schema.json",
  "globalDependencies": ["yarn.lock"],
  "globalEnv": ["DATABASE_URL", "NEXTAUTH_SECRET", ...]
}
```

### Biome Configuration
**Where:** `biome.json`
**How it works:** Biome replaces ESLint and Prettier. Configured for 110-char line width, 2-space indentation, LF line endings. Import organization follows a specific group order.
**Example:**
```json
// biome.json:29-39
"formatter": {
  "lineWidth": 110,
  "indentStyle": "space",
  "indentWidth": 2,
  "lineEnding": "lf"
}
```

Import organization groups:
```json
// biome.json:10-17
"groups": [
  ["**/__mocks__/**", "**/bookingScenario*"],
  [":PACKAGE_WITH_PROTOCOL:", ":PACKAGE:"],
  ["@calcom/**", "@ee/**"],
  ["@lib/**", "@components/**", "@server/**", "@trpc/**"],
  "~/**",
  ":PATH:"
]
```

### Docker Setup
**Where:** `docker-compose.yml`
**How it works:** Provides Postgres and Redis for local development.
**Example:**
```yaml
# docker-compose.yml:13-24
services:
  database:
    image: postgres
    environment:
      - POSTGRES_USER=unicorn_user
      - POSTGRES_PASSWORD=magical_password
      - POSTGRES_DB=calendso
  redis:
    image: redis:latest
    ports:
      - "${REDIS_PORT:-6379}:6379"
```

### Environment Variable Management
**Where:** `.env.example`, `.env.appStore.example`
**How it works:** Two env files:
- `.env` -- main app config (DATABASE_URL, NEXTAUTH_SECRET, CALENDSO_ENCRYPTION_KEY, etc.)
- `.env.appStore` -- third-party app credentials (GOOGLE_API_CREDENTIALS, STRIPE_PRIVATE_KEY, etc.)

On Windows, `packages/prisma/.env` symlink needs to be a real copy:
```bash
rm packages/prisma/.env && cp .env packages/prisma/.env
```

### Quick Start
```bash
# 1. Copy env files
cp .env.example .env

# 2. Set required secrets
# NEXTAUTH_SECRET (openssl rand -base64 32)
# CALENDSO_ENCRYPTION_KEY (openssl rand -base64 24)

# 3. Quick start (Docker Postgres + migrations + seed + dev)
yarn dx

# 4. Visit http://localhost:3000
# Default: pro@example.com / pro
# Admin: admin@example.com / ADMINadmin2022!
```

## Conventions

- **Package manager:** Yarn 4 (Berry) only -- not npm or pnpm
- **Linting:** Biome (not ESLint) -- run `yarn lint` and `yarn format`
- **Commit hooks:** Husky + lint-staged (configured in `lint-staged.config.mjs`)
- **Workspace commands:** `yarn workspace @calcom/<name> <command>`
- **Turborepo caching:** Tasks are cached based on `turbo.json` pipeline config
- **File naming:** kebab-case for files

## Dependencies

- **Runtime:** Node.js >= 18, PostgreSQL >= 13
- **Build:** Turborepo, Yarn 4 (Berry)
- **Lint/Format:** Biome
- **Infrastructure:** Docker (optional, for quick start)

## Gotchas

- Yarn 4 uses Plug'n'Play (PnP) or `node-modules` mode depending on `.yarnrc.yml` config
- Turborepo's `globalEnv` list in `turbo.json` is very long -- adding new env vars may require updating it
- The `postinstall` script runs Husky setup and turbo `post-install` tasks
- `yarn dx` requires Docker to be running
- Windows requires special handling for the `packages/prisma/.env` symlink

## Related Concepts

- [Testing Patterns](./testing-patterns.md) -- test scripts and configuration
- [Prisma and Database](./prisma-and-database.md) -- database commands
- [App Store Integrations](./app-store-integrations.md) -- app-store CLI
