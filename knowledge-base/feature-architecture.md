# Feature Architecture

> How features are organized in `packages/features/` with the lib/components/hooks/repositories/services/di pattern.

## Overview

`packages/features/` is where most Cal.com business logic lives. Each feature is a self-contained directory with a standardized internal structure. Newer features use dependency injection via `@evyweb/ioctopus`. Features connect to tRPC routers (which call feature logic) and the web app (which renders feature components).

## Key Locations

| Path | Purpose |
|------|---------|
| `packages/features/` | All domain features |
| `packages/features/di/` | Shared DI infrastructure (container, modules, tokens) |
| `packages/features/di/di.ts` | DI utilities (createContainer, createModule, bindModuleToClassOnToken) |
| `packages/features/di/tokens.ts` | Shared DI tokens |
| `packages/features/di/containers/` | Pre-built containers for shared services |
| `packages/features/di/modules/` | Shared DI modules (Prisma, User, Booking, etc.) |
| `packages/ee/` | Enterprise-only features |
| `packages/features/ee/` | Enterprise features nested within features package |

## Patterns

### Feature Directory Structure
**Where:** `packages/features/<feature-name>/`
**How it works:** Features follow a layered architecture pattern. Not all directories are present in every feature -- only what's needed.

```
packages/features/<feature>/
  lib/           # Core business logic, handlers, utilities
  components/    # React components for this feature
  hooks/         # React hooks
  repositories/  # Data access layer (Prisma calls)
  services/      # Service layer (business operations)
  di/            # Dependency injection bindings
    tokens.ts       # DI token symbols
    *.module.ts     # Module definitions (binding tokens to classes)
    *.container.ts  # Container factories (resolve services)
```

### Feature Inventory (Partial)

| Feature | Path | What It Does |
|---------|------|-------------|
| bookings | `packages/features/bookings/` | Booking creation, cancellation, rescheduling |
| availability | `packages/features/availability/` | User/event availability computation |
| eventtypes | `packages/features/eventtypes/` | Event type CRUD and configuration |
| schedules | `packages/features/schedules/` | User availability schedules |
| slots | `packages/features/slots/` | Slot notification handling |
| flags | `packages/features/flags/` | Feature flags system |
| credentials | `packages/features/credentials/` | Credential management |
| routing-forms | `packages/features/routing-forms/` | Form-based booking routing |
| insights | `packages/features/insights/` | Analytics and reporting |
| webhooks | `packages/features/webhooks/` | Webhook management |
| pbac | `packages/features/pbac/` | Permission-based access control |
| embed | `packages/features/embed/` | Embed widget logic |
| form-builder | `packages/features/form-builder/` | Dynamic form builder |
| organizations | `packages/features/organizations/` | Organization settings |

### Dependency Injection (DI)
**Where:** `packages/features/di/di.ts`
**How it works:** Uses `@evyweb/ioctopus` for IoC container. The pattern has three parts:

1. **Tokens** (`tokens.ts`): Unique symbols identifying services
2. **Modules** (`*.module.ts`): Bind tokens to class implementations with dependencies
3. **Containers** (`*.container.ts`): Create containers and resolve services

**Tokens Example:**
```ts
// packages/features/bookings/di/tokens.ts
export const BOOKING_DI_TOKENS = {
  REGULAR_BOOKING_SERVICE: Symbol("RegularBookingService"),
  REGULAR_BOOKING_SERVICE_MODULE: Symbol("RegularBookingServiceModule"),
  BOOKING_CANCEL_SERVICE: Symbol("BookingCancelService"),
  BOOKING_REFERENCE_REPOSITORY: Symbol("BookingReferenceRepository"),
  // ...
};
```

**Module Example:**
```ts
// packages/features/bookings/di/RegularBookingService.module.ts
const thisModule = createModule();
const loadModule = bindModuleToClassOnToken({
  module: thisModule,
  moduleToken,
  token,
  classs: RegularBookingService,
  depsMap: {
    prismaClient: prismaModuleLoader,
    bookingRepository: bookingRepositoryModuleLoader,
    luckyUserService: luckyUserServiceModuleLoader,
    // ... more dependencies
  },
});
export const moduleLoader = { token, loadModule } satisfies ModuleLoader;
```

**Container Example:**
```ts
// packages/features/bookings/di/RegularBookingService.container.ts
const regularBookingServiceContainer = createContainer();
export function getRegularBookingService(): RegularBookingService {
  regularBookingServiceModule.loadModule(regularBookingServiceContainer);
  return regularBookingServiceContainer.get<RegularBookingService>(regularBookingServiceModule.token);
}
```

### bindModuleToClassOnToken Utility
**Where:** `packages/features/di/di.ts:13-113`
**How it works:** Type-safe binding helper that ensures all constructor dependencies are provided. Supports both single dependency (`dep`) and multiple dependencies (`depsMap`). Automatically loads transitive module dependencies.

### Repository Pattern
**Where:** `packages/features/*/repositories/`
**How it works:** Repositories encapsulate database queries. Many use interfaces (`I<Name>Repository`) for testability and DI swapping.

Example repositories:
- `packages/features/bookings/repositories/BookingRepository.ts` (implements `IBookingRepository`)
- `packages/features/ee/teams/repositories/TeamRepository.ts`
- `packages/features/profile/repositories/ProfileRepository.ts`
- `packages/features/flags/repositories/PrismaFeatureRepository.ts`

### Service Layer
**Where:** `packages/features/*/services/`
**How it works:** Services contain business operations that orchestrate repositories, external APIs, and side effects.

Example services:
- `packages/features/bookings/lib/service/RegularBookingService.ts`
- `packages/features/ee/teams/services/teamService.ts`
- `packages/features/pbac/services/permission.service.ts`
- `packages/features/schedules/services/ScheduleService.ts`

### Shared DI Modules
**Where:** `packages/features/di/modules/`
**How it works:** Common dependencies are provided as shared modules that any feature can use.

| Module | Path | Provides |
|--------|------|----------|
| Prisma | `di/modules/Prisma.ts` | PrismaClient instance |
| User | `di/modules/User.ts` | User repository |
| Booking | `di/modules/Booking.ts` | Booking repository |
| LuckyUser | `di/modules/LuckyUser.ts` | Round-robin selection |
| AvailableSlots | `di/modules/AvailableSlots.ts` | Slot service |
| FeaturesRepository | `di/modules/FeaturesRepository.ts` | Feature flags |

### How Features Connect to tRPC
**Where:** tRPC handlers import from feature packages
**How it works:** tRPC router handlers (in `packages/trpc/`) import and call feature logic. The handler is the thin adapter between tRPC and the feature.
**Example:**
```ts
// tRPC handler imports feature service/logic
import { getBookings } from "@calcom/trpc/server/routers/viewer/bookings/get.handler";
// or uses DI container
import { getRegularBookingService } from "@calcom/features/bookings/di/RegularBookingService.container";
```

### Enterprise Features
**Where:** `packages/features/ee/`, `packages/ee/`
**How it works:** Enterprise-only features are in `packages/features/ee/` (within the features package) and `packages/ee/` (standalone). They include:
- `packages/features/ee/organizations/` -- Organization management
- `packages/features/ee/teams/` -- Advanced team features
- `packages/features/ee/workflows/` -- Workflow automation
- `packages/features/ee/managed-event-types/` -- Managed event types
- `packages/features/ee/round-robin/` -- Round-robin scheduling
- `packages/features/ee/billing/` -- Billing and credits
- `packages/ee/di/` -- Enterprise DI extensions
- `packages/ee/prisma-extensions/` -- Enterprise Prisma extensions

## Conventions

- Feature directories use kebab-case or camelCase (both exist historically)
- Newer code uses DI pattern; older code uses direct imports
- Repositories implement interfaces for testability
- DI tokens use Symbol() for type safety
- Module files export `moduleLoader = { token, loadModule }`
- Container files export `get<ServiceName>()` factory functions
- Test files are colocated (e.g., `*.test.ts`, `*.integration-test.ts`)

## Dependencies

- **DI:** `@evyweb/ioctopus` for IoC container
- **Data:** `@calcom/prisma` for database access
- **Types:** `@calcom/types` for shared interfaces
- **Used by:** tRPC handlers, web app components, API routes

## Gotchas

- Two DI approaches coexist: newer `@evyweb/ioctopus` pattern and older direct imports
- `packages/features/ee/` is within the features workspace, but `packages/ee/` is a separate workspace
- Not all features have all layers -- some only have `lib/`, others have the full stack
- The `di/` directory structure (`tokens.ts`, `*.module.ts`, `*.container.ts`) must follow the naming convention for the DI system to work
- `bindModuleToClassOnToken` requires either `dep` (single dependency) or `depsMap` (multiple), not both

## Related Concepts

- [tRPC Routers](./trpc-routers.md) -- routers call feature logic
- [Prisma and Database](./prisma-and-database.md) -- repositories use Prisma
- [Booking Flow](./booking-flow.md) -- primary example of the full pattern
