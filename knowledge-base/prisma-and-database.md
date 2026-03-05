# Prisma and Database

> How the PostgreSQL database, Prisma ORM, and data access patterns work in Cal.com.

## Overview

Cal.com uses PostgreSQL as its primary database, accessed via Prisma ORM. The schema is defined in a single file with generators for Zod types, Kysely types, and enums. A repository pattern is emerging in `packages/features/` for cleaner data access, alongside direct Prisma usage in older code.

## Key Locations

| Path | Purpose |
|------|---------|
| `packages/prisma/schema.prisma` | Single Prisma schema file (all models) |
| `packages/prisma/migrations/` | Migration history (timestamped directories) |
| `packages/prisma/zod/` | Generated Zod schemas from Prisma models |
| `packages/prisma/enums/` | Generated TypeScript enums |
| `packages/prisma/selects/` | Reusable Prisma select objects |
| `packages/prisma/client/` | Prisma client configuration |
| `packages/prisma/generated/prisma/` | Generated Prisma client output |
| `packages/kysely/types.ts` | Generated Kysely types for type-safe raw SQL |
| `packages/features/*/repositories/` | Repository pattern implementations |

## Patterns

### Schema Structure
**Where:** `packages/prisma/schema.prisma`
**How it works:** Uses PostgreSQL with `prisma-client` generator (client engine), plus generators for Zod, Kysely, and enums. Preview feature `views` is enabled.
**Example:**
```prisma
// packages/prisma/schema.prisma:4-40
datasource db {
  provider  = "postgresql"
  url       = env("DATABASE_URL")
  directUrl = env("DATABASE_DIRECT_URL")
}

generator client {
  provider        = "prisma-client"
  previewFeatures = ["views"]
  output          = "./generated/prisma"
  engineType      = "client"
}

generator zod {
  provider         = "zod-prisma-types"
  output           = "./zod"
  useMultipleFiles = true
}

generator kysely {
  provider = "prisma-kysely"
  output   = "../kysely"
  fileName = "types.ts"
}
```

### Key Models

| Model | Line | Purpose |
|-------|------|---------|
| `User` | ~406 | Core user model with auth, profile, settings |
| `EventType` | ~156 | Scheduling event configuration (duration, scheduling type, booking fields) |
| `Booking` | ~870 | Booking records with status, times, attendees |
| `Team` | ~569 | Teams and organizations (self-referential via `parentId`) |
| `Schedule` | ~969 | User availability schedules |
| `Availability` | ~984 | Time slots (days, startTime, endTime) linked to schedules |
| `Credential` | ~312 | Third-party app credentials (calendar, video, CRM) |
| `Host` | ~61 | Event type hosts (for round-robin, collective) with priority and weight |
| `DestinationCalendar` | ~354 | Where to create calendar events |

### SchedulingType Enum
**Where:** `packages/prisma/schema.prisma:42-46`
**Example:**
```prisma
enum SchedulingType {
  ROUND_ROBIN @map("roundRobin")
  COLLECTIVE  @map("collective")
  MANAGED     @map("managed")
}
```

### Zod Annotations in Schema
**Where:** Throughout `schema.prisma`
**How it works:** Uses `/// @zod` comments to customize generated Zod schemas. These import utilities from `packages/prisma/zod-utils.ts`.
**Example:**
```prisma
// packages/prisma/schema.prisma:158-160
/// @zod.string.min(1)
title             String
/// @zod.import(["import { eventTypeSlug } from '../../zod-utils'"]).custom.use(eventTypeSlug)
slug              String
```

### Repository Pattern
**Where:** `packages/features/*/repositories/`
**How it works:** Repositories wrap Prisma calls with domain-specific methods. Many implement an interface (`I<Name>Repository`) for dependency injection. The repository receives `PrismaClient` via constructor injection.
**Example:**
```ts
// packages/features/bookings/repositories/BookingRepository.ts:1-17
import type { PrismaClient } from "@calcom/prisma";
import type { Booking, Prisma } from "@calcom/prisma/client";
import { BookingStatus } from "@calcom/prisma/enums";
import { bookingMinimalSelect } from "@calcom/prisma/selects/booking";
import type { IBookingRepository } from "./IBookingRepository";
```

Notable repository files:
- `packages/features/bookings/repositories/BookingRepository.ts`
- `packages/features/ee/teams/repositories/TeamRepository.ts`
- `packages/features/ee/organizations/repositories/OrganizationRepository.ts`
- `packages/features/credentials/repositories/CredentialRepository.ts`
- `packages/features/flags/repositories/PrismaFeatureRepository.ts`
- `packages/features/profile/repositories/ProfileRepository.ts`

### Prisma Selects
**Where:** `packages/prisma/selects/`
**How it works:** Reusable select objects prevent over-fetching and ensure consistent field selection across queries.
**Example:**
```ts
// packages/features/bookings/repositories/BookingRepository.ts:6-9
import {
  bookingAuthorizationCheckSelect,
  bookingDetailsSelect,
  bookingMinimalSelect,
} from "@calcom/prisma/selects/booking";
```

### Migration Workflow
**How it works:**
1. Edit `packages/prisma/schema.prisma`
2. Run `yarn prisma migrate dev` to create a migration
3. Run `yarn prisma db push` for quick schema push without migration files
4. Migrations are in `packages/prisma/migrations/` with timestamped directories
5. Latest migrations (as of this codebase): `20260219000000_add_fallback_action_to_queued_form_response`

### Kysely for Type-Safe Raw SQL
**Where:** `packages/kysely/types.ts`
**How it works:** The `prisma-kysely` generator produces TypeScript types from the Prisma schema. Used when complex queries are needed beyond Prisma's query builder.

## Conventions

- All models are in a single `schema.prisma` file (no multi-file schema)
- Repository classes are named `<Domain>Repository.ts` and implement `I<Domain>Repository.ts` interfaces
- Use `@calcom/prisma/selects/` for shared select objects
- Enum values use `@map()` to store snake_case in DB while exposing PascalCase in code
- Zod validation annotations are embedded in schema comments
- Integration test files for repositories use `.integration-test.ts` suffix
- The Prisma client import path is `@calcom/prisma` or `@calcom/prisma/client`
- Enums are imported from `@calcom/prisma/enums`

## Dependencies

- **Database:** PostgreSQL >= 13
- **ORM:** Prisma with `prisma-client` engine
- **Generators:** `zod-prisma-types`, `prisma-kysely`, `prisma-enum-generator`
- **Used by:** All backend code (tRPC handlers, services, repositories)

## Gotchas

- The `DATABASE_DIRECT_URL` is for direct connections (migrations), while `DATABASE_URL` may go through a connection pooler
- Generated files (`packages/prisma/generated/`, `packages/prisma/zod/`, `packages/kysely/types.ts`) should not be manually edited
- Some models have deprecated fields (e.g., `EventType.price`, `Booking.scheduledJobs`) -- check comments
- The `Team` model doubles as both teams and organizations (`isOrganization` flag, `parentId` for hierarchy)
- On Windows, the `packages/prisma/.env` symlink may need to be replaced with a real copy

## Related Concepts

- [Feature Architecture](./feature-architecture.md) -- repositories live in feature packages
- [tRPC Routers](./trpc-routers.md) -- handlers access Prisma via ctx or repositories
- [Booking Flow](./booking-flow.md) -- the Booking model is central
