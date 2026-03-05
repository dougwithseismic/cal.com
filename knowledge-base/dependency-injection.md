# Dependency Injection

> Cal.com uses a custom DI system built on `@evyweb/ioctopus` with modules, containers, and Symbol-based tokens to wire services and repositories.

## Overview

The DI system follows a module-based architecture where:
- **Tokens** are Symbols that identify services/repositories
- **Modules** bind tokens to implementations (classes or factories)
- **Containers** load modules and resolve dependencies
- **Module loaders** provide a standardized way to load modules into containers

This pattern is used for core services like booking, availability, webhooks, and feature flags. It enables swapping implementations (e.g., open-source vs EE Prisma bindings, real vs noop Redis).

## Key Locations

| Path | Purpose |
|------|---------|
| `packages/features/di/di.ts` | Core DI utilities: `createContainer`, `createModule`, `bindModuleToClassOnToken` |
| `packages/features/di/tokens.ts` | Central token registry aggregating all DI tokens |
| `packages/features/di/modules/` | Module definitions for shared services (Prisma, User, Booking, etc.) |
| `packages/features/di/containers/` | Container setup files that wire modules together |
| `packages/features/*/di/` | Feature-specific DI: tokens, modules, containers |
| `packages/ee/di/modules/PrismaEE.ts` | Enterprise Prisma binding with usage tracking |

## Patterns

### Token Definition
**Where:** `packages/features/di/tokens.ts`, `packages/features/bookings/di/tokens.ts`
**How it works:** Tokens are Symbols grouped by feature domain. The central `DI_TOKENS` object spreads in tokens from all features.

**Example:**
```typescript
export const BOOKING_DI_TOKENS = {
  REGULAR_BOOKING_SERVICE: Symbol("RegularBookingService"),
  REGULAR_BOOKING_SERVICE_MODULE: Symbol("RegularBookingServiceModule"),
  BOOKING_REFERENCE_REPOSITORY: Symbol("BookingReferenceRepository"),
  // ...
};

// In packages/features/di/tokens.ts:
export const DI_TOKENS = {
  PRISMA_CLIENT: Symbol("PrismaClient"),
  REDIS_CLIENT: Symbol("RedisClient"),
  ...BOOKING_DI_TOKENS,
  ...HASHED_LINK_DI_TOKENS,
  ...OAUTH_DI_TOKENS,
  // ... all feature tokens spread in
};
```

### Module Definition with `bindModuleToClassOnToken`
**Where:** `packages/features/bookings/di/RegularBookingService.module.ts`
**How it works:** `bindModuleToClassOnToken` is a type-safe helper that binds a class to a token and declares its dependency map. Each dependency is another module loader. The function returns a `loadModule` function.

**Example:**
```typescript
const thisModule = createModule();
const token = DI_TOKENS.REGULAR_BOOKING_SERVICE;
const moduleToken = DI_TOKENS.REGULAR_BOOKING_SERVICE_MODULE;

const loadModule = bindModuleToClassOnToken({
  module: thisModule,
  moduleToken,
  token,
  classs: RegularBookingService,
  depsMap: {
    prismaClient: prismaModuleLoader,
    bookingRepository: bookingRepositoryModuleLoader,
    luckyUserService: luckyUserServiceModuleLoader,
    userRepository: userRepositoryModuleLoader,
    // ...
  },
});

export const moduleLoader = { token, loadModule } satisfies ModuleLoader;
```

### Container Setup
**Where:** `packages/features/bookings/di/RegularBookingService.container.ts`
**How it works:** A container is created, a module is loaded into it, then the service is resolved by token.

**Example:**
```typescript
import { createContainer } from "@calcom/features/di/di";
import { moduleLoader as regularBookingServiceModule } from "./RegularBookingService.module";

const regularBookingServiceContainer = createContainer();

export function getRegularBookingService(): RegularBookingService {
  regularBookingServiceModule.loadModule(regularBookingServiceContainer);
  return regularBookingServiceContainer.get<RegularBookingService>(regularBookingServiceModule.token);
}
```

### Factory-Based Module Binding
**Where:** `packages/features/di/modules/Prisma.ts`
**How it works:** For simple bindings (like singletons), modules use `.bind(token).toFactory()` directly.

**Example:**
```typescript
export const prismaModule = createModule();
prismaModule.bind(DI_TOKENS.PRISMA_CLIENT).toFactory(() => prisma, "singleton");
prismaModule.bind(DI_TOKENS.READ_ONLY_PRISMA_CLIENT).toFactory(() => readonlyPrisma, "singleton");
```

### EE vs Open-Source Bindings
**Where:** `packages/ee/di/modules/PrismaEE.ts` vs `packages/features/di/modules/Prisma.ts`
**How it works:** The EE Prisma module adds usage tracking via a Prisma extension. Both bind to the same `DI_TOKENS.PRISMA_CLIENT` token, so the container gets the EE version when loaded from the EE module.

**Example (EE):**
```typescript
const prismaWithUsageTracking = prisma.$extends(usageTrackingExtention(prisma));
prismaEEModule.bind(token).toFactory(() => prismaWithUsageTracking, "singleton");
```

### Redis with Fallback
**Where:** `packages/features/redis/di/redisModule.ts`
**How it works:** The module conditionally binds either `RedisService` (real Upstash client) or `NoopRedisService` based on environment variable availability.

**Example:**
```typescript
redisModule.bind(DI_TOKENS.REDIS_CLIENT).toFactory(() => {
  if (process.env.UPSTASH_REDIS_REST_URL && process.env.UPSTASH_REDIS_REST_TOKEN) {
    return new RedisService();
  }
  return new NoopRedisService();
}, "singleton");
```

## Conventions

- Every DI token has a paired `_MODULE` token (e.g., `REGULAR_BOOKING_SERVICE` + `REGULAR_BOOKING_SERVICE_MODULE`)
- Module files are named `*.module.ts`, container files `*.container.ts`, token files `tokens.ts`
- Feature DI lives in `packages/features/<feature>/di/`
- The `ModuleLoader` type is `{ token: symbol; loadModule: (container: Container) => void }`
- Dependency maps in `bindModuleToClassOnToken` must match the constructor parameter names of the target class

## Dependencies

- `@evyweb/ioctopus` - The underlying IoC container library
- Token symbols are the glue between modules and containers

## Gotchas

- `bindModuleToClassOnToken` requires either `dep` (single dependency) or `depsMap` (multiple dependencies), never both
- Module loading is idempotent -- calling `loadModule` multiple times on the same container is safe due to the `moduleToken` guard
- The central `DI_TOKENS` in `packages/features/di/tokens.ts` imports and spreads tokens from many feature packages. Adding a new feature's tokens requires updating this file
- Constructor dependency names must exactly match the keys in `depsMap`

## Related Concepts

- [Caching and Redis](./caching-and-redis.md) - Redis is injected via DI
- [Cron and Background Jobs](./cron-and-background-jobs.md) - Tasker services use DI containers
