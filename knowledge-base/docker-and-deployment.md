# Docker and Deployment

> Cal.com provides Docker Compose for local development (Postgres + Redis + app), a multi-stage Dockerfile for production, and `yarn dx` as the primary local setup command.

## Overview

The project supports multiple deployment targets:
- **Local development** via Docker Compose (database + Redis) and `yarn dx`
- **Docker production** via a multi-stage Dockerfile that builds a standalone Next.js app
- **Vercel** as the primary cloud deployment platform (no `vercel.json` in repo; configured via dashboard)
- **API v2** has its own Dockerfile for independent deployment

## Key Locations

| Path | Purpose |
|------|---------|
| `docker-compose.yml` | Root Docker Compose: Postgres, Redis, web app, API v2, Prisma Studio |
| `Dockerfile` | Production multi-stage build for `apps/web` |
| `apps/api/v2/Dockerfile` | Separate Dockerfile for API v2 |
| `scripts/start.sh` | Container entrypoint: migration + seed + start |
| `packages/prisma/package.json` | `dx` script: `db-setup` (up + deploy + seed) |
| `packages/emails/docker-compose.yml` | Email preview Docker Compose |
| `apps/web/package.json` | Web app `dx` script |
| `package.json` | Root `dx` script: `turbo run dx` |

## Patterns

### Local Development with `yarn dx`
**Where:** `package.json` (root), `packages/prisma/package.json`
**How it works:** `yarn dx` at the root triggers `turbo run dx`, which runs `dx` scripts across packages in dependency order:
1. `packages/prisma/dx` -> `yarn db-setup` -> `db-up` (Docker), `db-deploy` (migrations), `db-seed`
2. `packages/emails/dx` -> `docker compose up -d` (email preview)
3. `packages/ui/dx` -> builds icons
4. `apps/web/dx` -> `yarn dev`

**Commands:**
```bash
# Full setup from scratch
yarn dx

# Individual steps
yarn --cwd packages/prisma db-up        # Start Postgres container
yarn --cwd packages/prisma db-deploy    # Run migrations
yarn --cwd packages/prisma db-seed      # Seed database
yarn --cwd packages/prisma db-reset     # Nuke and re-setup
yarn --cwd packages/prisma db-studio    # Open Prisma Studio
```

### Docker Compose Services
**Where:** `docker-compose.yml`
**How it works:** Defines 5 services: `database` (Postgres), `redis`, `calcom` (web app), `calcom-api` (API v2), and `studio` (Prisma Studio).

**Service details:**
```yaml
services:
  database:
    image: postgres
    environment:
      POSTGRES_USER: unicorn_user
      POSTGRES_PASSWORD: magical_password
      POSTGRES_DB: calendso

  redis:
    image: redis:latest
    ports: ["${REDIS_PORT:-6379}:6379"]

  calcom:
    build: { context: ., dockerfile: Dockerfile }
    ports: ["3000:3000"]
    env_file: .env
    depends_on: [database]

  calcom-api:
    build: { context: ., dockerfile: apps/api/v2/Dockerfile }
    ports: ["${API_PORT:-80}:${API_PORT:-80}"]
    depends_on: [database, redis]

  studio:           # Prisma Studio (optional, comment out in production)
    ports: ["5555:5555"]
    command: ["npx", "prisma", "studio"]
```

### Production Dockerfile (Multi-Stage)
**Where:** `Dockerfile`
**How it works:** Three stages: `builder` (build), `builder-two` (URL replacement), `runner` (final image).

**Stage 1: builder**
- Base: `node:20`
- Accepts build args: `NEXT_PUBLIC_WEBAPP_URL`, `DATABASE_URL`, `NEXTAUTH_SECRET`, `CALENDSO_ENCRYPTION_KEY`, etc.
- Prunes with `turbo prune`, installs deps, builds tRPC, embed-core, and web app
- Uses `BUILD_STANDALONE=true` for Next.js standalone output
- Sets `MAX_OLD_SPACE_SIZE=6144` (6GB) for the build

**Stage 2: builder-two**
- Replaces placeholder URLs with actual `NEXT_PUBLIC_WEBAPP_URL`
- Copies scripts and makes them executable

**Stage 3: runner**
- Base: `node:20`
- Installs `netcat-openbsd` and `wget` for health checks
- Exposes port 3000
- Health check: `wget --spider http://localhost:3000`
- Entrypoint: `scripts/start.sh`

### Container Startup Script
**Where:** `scripts/start.sh`
**How it works:** Runs at container start to handle URL replacement, wait for database, run migrations, seed app store, then start the app.

```bash
#!/bin/sh
set -x
# Replace URLs if BUILT_NEXT_PUBLIC_WEBAPP_URL differs from runtime NEXT_PUBLIC_WEBAPP_URL
scripts/replace-placeholder.sh "$BUILT_NEXT_PUBLIC_WEBAPP_URL" "$NEXT_PUBLIC_WEBAPP_URL"
# Wait for database to be ready
scripts/wait-for-it.sh ${DATABASE_HOST} -- echo "database is up"
# Run database migrations
npx prisma migrate deploy --schema /calcom/packages/prisma/schema.prisma
# Seed the app store
npx ts-node --transpile-only /calcom/scripts/seed-app-store.ts
# Start the application
yarn start
```

### Environment Variable Management
**Where:** `docker-compose.yml`, `Dockerfile`
**How it works:** Build-time variables are passed as `ARG` in Dockerfile, runtime variables come from `.env` file via `env_file`. Some variables need to be available at both build and runtime (like `NEXT_PUBLIC_WEBAPP_URL`).

**Critical environment variables:**
| Variable | Purpose |
|----------|---------|
| `DATABASE_URL` | PostgreSQL connection string |
| `NEXTAUTH_SECRET` | NextAuth.js session encryption |
| `CALENDSO_ENCRYPTION_KEY` | Legacy credential encryption key |
| `NEXT_PUBLIC_WEBAPP_URL` | Public-facing URL of the app |
| `NEXT_PUBLIC_API_V2_URL` | API v2 endpoint URL |
| `CRON_SECRET` | Authentication for cron endpoints |
| `STRIPE_PRIVATE_KEY` | Stripe platform key |
| `STRIPE_WEBHOOK_SECRET` | Stripe webhook verification |
| `UPSTASH_REDIS_REST_URL` | Redis endpoint (optional) |
| `UPSTASH_REDIS_REST_TOKEN` | Redis auth token (optional) |
| `CALCOM_KEYRING_CREDENTIALS_CURRENT` | Current encryption key ID |

### Database Migration in Deployment
**Where:** `scripts/start.sh`, `packages/prisma/package.json`
**How it works:** In Docker, migrations run automatically at container start via `prisma migrate deploy`. For local dev, `yarn dx` handles this through `db-deploy`. There is also an `auto-migrations.ts` script that runs as part of the prisma build step.

### Prisma Database Management Scripts
**Where:** `packages/prisma/package.json`
**How it works:** Complete set of database lifecycle commands.

```
db-up       -> docker compose up -d          (start Postgres container)
db-deploy   -> prisma migrate deploy         (apply migrations)
db-migrate  -> prisma migrate dev            (create new migration)
db-seed     -> prisma db seed                (seed database)
db-reset    -> db-nuke + db-setup            (full reset)
db-nuke     -> docker compose down --volumes (destroy everything)
db-studio   -> prisma studio                 (GUI browser)
dx          -> db-setup                      (setup shorthand)
```

## Conventions

- The root `yarn dx` is the one-command setup for new developers
- Docker Compose is for local dev infrastructure only (Postgres, Redis), not for running the app locally
- The production Dockerfile uses a URL placeholder strategy to allow build-time and runtime URLs to differ
- All container health checks use HTTP probes
- Database seeding (`seed-app-store.ts`) runs on every container start to ensure app store entries exist
- Prisma Studio is included in Docker Compose but should be removed/commented out in production

## Dependencies

- Docker and Docker Compose for local infrastructure
- Node.js 20 (pinned in Dockerfile)
- turbo for monorepo task orchestration
- Prisma CLI for migrations

## Gotchas

- The Dockerfile uses `BUILD_STANDALONE=true` which changes Next.js output structure -- the standalone build includes only necessary files
- `NEXT_PUBLIC_WEBAPP_URL` is set to a placeholder at build time and replaced at runtime via `replace-placeholder.sh`. If the values match, no replacement occurs
- The `MAX_OLD_SPACE_SIZE` is set to 6144MB (6GB) for the build stage -- builds may fail on machines with less memory
- `scripts/wait-for-it.sh` blocks until the database is reachable, preventing race conditions
- Docker Compose database uses default credentials (`unicorn_user`/`magical_password`) -- change for any non-local deployment
- The `db-nuke` command destroys volumes -- all database data is permanently lost
- There is no `vercel.json` in the repo; Vercel configuration is managed via the Vercel dashboard
- API v2 has its own Dockerfile and runs as a separate service

## Related Concepts

- [Prisma and Database](./prisma-and-database.md) - Migration and schema management
- [Cron and Background Jobs](./cron-and-background-jobs.md) - Cron endpoints need external scheduling in deployment
- [Monorepo and Tooling](./monorepo-and-tooling.md) - Turbo orchestrates the `dx` command across packages
