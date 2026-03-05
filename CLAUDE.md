# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What is Cal.com?

Cal.com is an open-source scheduling infrastructure platform (Calendly alternative). It's a Yarn 4 monorepo managed by Turborepo.

## Tech Stack

- **Frontend:** Next.js (App Router + Pages Router migration in progress), React, Tailwind CSS
- **API layer:** tRPC (internal), NestJS (API v2 / Platform API)
- **Database:** PostgreSQL via Prisma ORM (with Kysely for type-safe raw queries)
- **Testing:** Vitest (unit/integration), Playwright (E2E)
- **Linting/Formatting:** Biome (not ESLint)
- **Package Manager:** Yarn 4 (Berry) — do NOT use npm or pnpm

## Common Commands

```bash
# Install dependencies
yarn

# Quick start (requires Docker — starts Postgres, runs migrations, seeds, launches dev)
yarn dx

# Dev server only (no DB setup)
yarn dev

# Build
yarn build

# Run all unit tests
yarn test

# Run a single test file
TZ=UTC yarn vitest run path/to/file.test.ts

# Run tests in watch mode
yarn tdd

# Run E2E tests (seeds DB first)
yarn test-e2e

# Type checking
yarn type-check

# Lint
yarn lint
yarn lint:fix

# Format
yarn format

# Database commands
yarn prisma migrate dev          # Create migration
yarn prisma db push              # Push schema without migration
yarn db-seed                     # Seed database
yarn db-studio                   # Prisma Studio at localhost:5555

# Run a command in a specific workspace
yarn workspace @calcom/web <command>
yarn workspace @calcom/prisma <command>
```

## Monorepo Structure

### Apps
- `apps/web` — Main Next.js application (the scheduling UI). Uses both App Router (`app/`) and Pages Router (`pages/`).
- `apps/api/v1` — REST API v1 (Next.js API routes)
- `apps/api/v2` — Platform API v2 (NestJS standalone app). Has its own Jest config for testing.

### Key Packages
- `packages/prisma` — Prisma schema, migrations, seed script. Schema at `packages/prisma/schema.prisma`. Generates Zod types (`packages/prisma/zod/`) and Kysely types (`packages/kysely/types.ts`).
- `packages/trpc` — tRPC routers. Main router tree: `server/routers/viewer/` (authenticated routes) and `server/routers/publicViewer/`.
- `packages/features` — Domain logic organized by feature (bookings, availability, event types, workflows, routing-forms, organizations, insights, slots, etc.). This is where most business logic lives.
- `packages/lib` — Shared utilities, helpers, server config, and cross-cutting concerns.
- `packages/ui` — Shared UI component library (React + Tailwind).
- `packages/emails` — Email templates and sending logic.
- `packages/app-store` — Third-party integration apps (Google Calendar, Zoom, Stripe, etc.). Each app is a subfolder with standardized structure (`config.json`, `api/`, `lib/`, `components/`).
- `packages/embeds` — Embeddable booking widgets (embed-core, embed-react, embed-snippet).
- `packages/platform` — Platform SDK packages (atoms, constants, enums, types, utils, libraries).
- `packages/ee` — Enterprise-only features (DI extensions, Prisma extensions).
- `packages/i18n` — Internationalization.

## Architecture Patterns

### Data Flow
User action → Next.js page/App Router → tRPC mutation/query → Feature logic (`packages/features`) → Prisma DB access

### tRPC Router Organization
Routers in `packages/trpc/server/routers/viewer/` map to feature domains: `bookings`, `eventTypes`, `availability`, `slots`, `workflows`, `teams`, `organizations`, etc. The main router is assembled in `_router.tsx` files.

### Feature Package Pattern
Features in `packages/features/` typically contain:
- `lib/` — Core business logic and handlers
- `components/` — React components
- `hooks/` — React hooks
- `repositories/` — Data access layer (newer pattern)
- `services/` — Service layer (newer pattern)
- `di/` — Dependency injection bindings

### Booking Flow
The core booking flow spans multiple packages:
1. **Slot selection:** `packages/features/slots` computes available slots
2. **Booker UI:** `packages/features/bookings/Booker` renders the booking widget
3. **Booking creation:** `packages/features/bookings/lib` handles booking logic
4. **Calendar integration:** `packages/app-store/*/` calendar apps handle event creation

### App Store Architecture
Each integration app in `packages/app-store/` follows a convention:
- `config.json` — App metadata
- `api/` — API route handlers (webhook receivers, OAuth callbacks)
- `lib/` — Integration logic (calendar service, CRM service, etc.)
- `components/` — Setup/config UI components
- Generated files are managed by `packages/app-store-cli`

### Web App Routing
`apps/web` is migrating from Pages Router to App Router:
- `app/(booking-page-wrapper)/` — Public booking pages
- `app/(use-page-wrapper)/` — Authenticated dashboard pages (event-types, bookings, availability, settings, teams, apps)
- `pages/` — Legacy pages still being migrated

## Testing

### Vitest (Unit/Integration)
- Config at root `vitest.config.mts`
- Three modes: default (unit), integration (`VITEST_MODE=integration`), timezone (`VITEST_MODE=timezone`)
- Test files: `*.test.ts`, `*.integration-test.ts`, `*.timezone.test.ts`
- API v2 tests use Jest separately (`apps/api/v2/jest.config.ts`)

### Playwright (E2E)
- Tests in `apps/web/playwright/`
- Run with `yarn e2e` (web), `yarn e2e:app-store`, `yarn e2e:embed`

## Local Development Setup

### Prerequisites
- Node.js >= 18, Yarn 4, PostgreSQL >= 13
- Docker (optional, for `yarn dx` quick start)

### Quick Start
1. `cp .env.example .env` and set `NEXTAUTH_SECRET` (use `openssl rand -base64 32`) and `CALENDSO_ENCRYPTION_KEY` (use `openssl rand -base64 24`)
2. **Windows:** replace the `packages/prisma/.env` symlink with a real copy: `rm packages/prisma/.env && cp .env packages/prisma/.env`
3. `yarn dx` (starts Docker Postgres, runs migrations, seeds, launches dev server)
4. Visit `http://localhost:3000` — default logins: `pro@example.com` / `pro`, `admin@example.com` / `ADMINadmin2022!`

### Manual Setup (without Docker)
1. Set `DATABASE_URL` in `.env` pointing to your Postgres instance
2. `yarn`
3. `yarn workspace @calcom/prisma db-migrate`
4. `yarn db-seed`
5. `yarn dev`

## Environment Variables
- `.env.example` — Main env template (copy to `.env`)
- `.env.appStore.example` — App store credentials (copy to `.env.appStore`)
- Key variables: `DATABASE_URL`, `NEXTAUTH_SECRET`, `CALENDSO_ENCRYPTION_KEY`, `NEXT_PUBLIC_WEBAPP_URL`

## Cal.com Agent Documentation

The repo ships with its own agent documentation at `agents/` in the project root:
- `agents/README.md` — Index of all rules and skills
- `agents/commands.md` — Full command reference with examples
- `agents/knowledge-base.md` — Domain-specific knowledge (managed event types, org/team model, OAuth clients, workflows vs webhooks, calendar cache, round-robin scheduling)
- `agents/rules/` — 45 coding rules covering architecture, quality, data layer, API, performance, testing, CI/CD, and patterns. Each follows a structured template with impact ratings, correct/incorrect examples.
- `agents/skills/` — Pre-built skills for cal.com API, Vercel/React best practices, and web design guidelines

These should be consulted when making changes to understand cal.com's established conventions.

## Knowledge Base

Deep-dive reference docs live in `knowledge-base/` at the project root. Each file documents how a specific concept is used in THIS codebase with real file paths, code snippets, and patterns. Use `/distill-concept <topic>` to generate new entries.

| Category | Files |
|----------|-------|
| **Core architecture** | `feature-architecture.md`, `monorepo-and-tooling.md`, `dependency-injection.md` |
| **Frontend** | `react-hooks.md`, `next-js-routing.md`, `ui-components.md`, `embed-system.md` |
| **Data & API** | `trpc-routers.md`, `prisma-and-database.md`, `api-v2-nestjs.md` |
| **Scheduling domain** | `booking-flow.md`, `availability-and-scheduling.md`, `event-types.md`, `routing-forms.md` |
| **Platform** | `organizations-and-teams.md`, `platform-sdk-atoms.md`, `workflows-and-automations.md` |
| **Infrastructure** | `authentication-and-authorization.md`, `credentials-and-oauth.md`, `email-and-notifications.md`, `caching-and-redis.md`, `payments-and-stripe.md`, `cron-and-background-jobs.md`, `docker-and-deployment.md` |
| **Meta** | `testing-patterns.md`, `internationalization.md` |

## Custom Skills

Project skills in `.claude/skills/`:

| Skill | Purpose |
|-------|---------|
| `/distill-concept <topic>` | Generate a knowledge base entry by analyzing codebase patterns |
| `/create-skill <name> <desc>` | Scaffold a new skill with proper SKILL.md structure |
| `/create-agent <name> <desc>` | Scaffold a new subagent configuration |
| `/skill-and-agent-factory` | Unified factory for creating skills, agents, or both |
| `/journal-write [summary]` | Write a journal entry (SQLite + timestamped markdown) |
| `/journal-read [recent\|today\|search\|last N]` | Query journal entries |
| `/issues-sync [gh flags]` | Sync GitHub issues into local SQLite (read-only, never posts) |
| `/issues-list [open\|bugs\|features\|search\|priority]` | List/filter tracked issues from local DB |
| `/issues-view <number> [--refresh]` | View full issue details with local tracking metadata |
| `/issues-triage <number> <action> [value]` | Set priority, status, or notes on a tracked issue |
| `/contribution-check [--skip-lint\|--skip-types]` | Pre-flight validation against CONTRIBUTING.md + 45 agent rules (never pushes) |
| `/pr-prepare <issue-number> [--draft]` | Draft PR title + body using Cal.com template, stops for user review (never auto-creates) |
| `/task-create <title> [flags]` | Create a new task (SQLite + folder in `.claude/tasks/`) |
| `/task-list [todo\|in-progress\|done\|all]` | List/filter tasks by status or priority |
| `/task-view <id or slug>` | View full task details including TASK.md notes |
| `/task-update <id> <field> <value>` | Update task field (status, priority, tags, notes, etc.) |
| `/task-start <id or slug>` | Mark task as in-progress with timestamp |
| `/task-done <id or slug> [summary]` | Mark task as done with completion time |

## Custom Agents

Project agents in `.claude/agents/`:

| Agent | Purpose |
|-------|---------|
| `github-issues` | Manages GitHub issue tracking — sync, query, triage, and codebase correlation via `gh` CLI |
| `contribution-guard` | Read-only reviewer — checks diffs against all 45 coding rules + CONTRIBUTING.md (never pushes or creates PRs) |

## Journal System

Session activity is auto-logged to `.claude/journal/journal.db` via a `Stop` hook. Manual entries via `/journal-write` save to both SQLite and `.claude/journal/entries/` as timestamped markdown. Query with `/journal-read`.

## GitHub Issues Tracking

The journal database includes a `github_issues` table for tracking upstream issues locally. Data is synced from GitHub via `gh` CLI (read-only — never posts or modifies anything on GitHub). Use `/issues-sync` to pull issues, `/issues-list` to browse, `/issues-view` for details, and `/issues-triage` to set local priority/status/notes. The `github-issues` agent can handle bulk operations and codebase correlation. Sync script at `.claude/scripts/sync-issues.js`.

## Task Tracking

Local task management stored in `journal.db` (`tasks` table) with per-task folders at `.claude/tasks/<slug>/`. Each task folder contains a `TASK.md` with status, description, and working notes. Tasks have statuses (`todo`, `in-progress`, `done`, `blocked`) and priorities (`critical`, `high`, `medium`, `low`). Tasks can optionally link to a GitHub issue. Use `/task-create` to add tasks, `/task-start` and `/task-done` for quick status changes, `/task-list` to see active work, and `/task-view` for full details.
