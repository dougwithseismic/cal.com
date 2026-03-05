# Caching and Redis

> Cal.com uses Upstash Redis (via REST API) for caching with decorator-based memoization, and Unkey for rate limiting. Redis is optional -- a NoopRedisService provides graceful fallback.

## Overview

The caching system has three main components:
1. **Redis service** - An Upstash Redis client wrapped in an `IRedisService` interface with a noop fallback
2. **Memoize/Unmemoize decorators** - TypeScript decorators that cache method results in Redis
3. **Rate limiting** - Uses Unkey (not Redis directly) for request rate limiting

Redis is injected via the DI system. When Upstash credentials are not configured, the `NoopRedisService` silently returns null/empty values, making Redis effectively optional.

## Key Locations

| Path | Purpose |
|------|---------|
| `packages/features/redis/IRedisService.d.ts` | Interface defining Redis operations |
| `packages/features/redis/RedisService.ts` | Real Upstash Redis implementation |
| `packages/features/redis/NoopRedisService.ts` | No-op fallback when Redis is unavailable |
| `packages/features/redis/di/redisModule.ts` | DI module that conditionally binds real or noop Redis |
| `packages/features/di/containers/Redis.ts` | DI container exposing `getRedisService()` |
| `packages/features/cache/decorators/Memoize.ts` | `@Memoize` decorator for caching method results |
| `packages/features/cache/decorators/Unmemoize.ts` | `@Unmemoize` decorator for cache invalidation |
| `packages/features/cache/decorators/types.ts` | Default TTL constant (5 minutes) |
| `packages/lib/rateLimit.ts` | Rate limiting via Unkey |
| `packages/lib/checkRateLimitAndThrowError.ts` | Rate limit check helper that throws HttpError |
| `packages/features/di/modules/SelectedSlots.ts` | Selected slots repository (uses Prisma, not Redis) |

## Patterns

### Redis Service Interface
**Where:** `packages/features/redis/IRedisService.d.ts`
**How it works:** Defines a minimal Redis interface with get, set, del, expire, lrange, and lpush operations.

**Example:**
```typescript
export interface IRedisService {
  get: <TData>(key: string) => Promise<TData | null>;
  set: <TData>(key: string, value: TData, opts?: { ttl?: number }) => Promise<"OK" | TData | null>;
  expire: (key: string, seconds: number) => Promise<0 | 1>;
  lrange: <TResult>(key: string, start: number, end: number) => Promise<TResult[]>;
  lpush: <TData>(key: string, ...elements: TData[]) => Promise<number>;
  del: (key: string) => Promise<number>;
}
```

### Conditional Redis Binding via DI
**Where:** `packages/features/redis/di/redisModule.ts`
**How it works:** The module checks for Upstash env vars at binding time. If present, binds `RedisService`; otherwise binds `NoopRedisService`. Both are singletons.

**Example:**
```typescript
redisModule.bind(DI_TOKENS.REDIS_CLIENT).toFactory(() => {
  if (process.env.UPSTASH_REDIS_REST_URL && process.env.UPSTASH_REDIS_REST_TOKEN) {
    return new RedisService();
  }
  return new NoopRedisService();
}, "singleton");
```

### Getting the Redis Service
**Where:** `packages/features/di/containers/Redis.ts`
**How it works:** A pre-configured container exposes `getRedisService()` for use throughout the codebase.

**Example:**
```typescript
import { getRedisService } from "@calcom/features/di/containers/Redis";

const redis = getRedisService();
const value = await redis.get<MyType>("cache-key");
```

### @Memoize Decorator
**Where:** `packages/features/cache/decorators/Memoize.ts`
**How it works:** A TypeScript method decorator that caches the return value in Redis. Accepts a `key` function to generate cache keys from method arguments, an optional `ttl` (default 5 minutes), and an optional Zod `schema` for validation. Redis failures are caught and logged -- they never break the decorated method.

**Example:**
```typescript
import { Memoize } from "@calcom/features/cache";

class FeatureRepository {
  @Memoize({
    key: (teamId: number) => `team-features:${teamId}`,
    ttl: 10 * 60 * 1000, // 10 minutes
    schema: featureSchema,  // optional Zod validation
  })
  async getTeamFeatures(teamId: number) {
    return this.prisma.feature.findMany({ where: { teamId } });
  }
}
```

### @Unmemoize Decorator
**Where:** `packages/features/cache/decorators/Unmemoize.ts`
**How it works:** Invalidates cache keys after a method executes. The `keys` function returns an array of cache keys to delete.

**Example:**
```typescript
import { Unmemoize } from "@calcom/features/cache";

class FeatureRepository {
  @Unmemoize({
    keys: (teamId: number) => [`team-features:${teamId}`],
  })
  async updateTeamFeature(teamId: number, data: FeatureData) {
    return this.prisma.feature.update({ where: { teamId }, data });
  }
}
```

### Rate Limiting with Unkey
**Where:** `packages/lib/rateLimit.ts`
**How it works:** Rate limiting uses Unkey (not Redis) with multiple tiers. If `UNKEY_ROOT_KEY` is not set, rate limiting is disabled (always allows). Banned IPs are forced into `forcedSlowMode`.

**Example:**
```typescript
import { checkRateLimitAndThrowError } from "@calcom/lib/checkRateLimitAndThrowError";

await checkRateLimitAndThrowError({
  rateLimitingType: "core",   // 10 req/60s
  identifier: userIp,
});
```

**Rate limit tiers:**
| Type | Limit | Duration |
|------|-------|----------|
| `core` | 10 | 60s |
| `common` | 200 | 60s |
| `api` | 30 | 60s |
| `ai` | 20 | 1 day |
| `sms` | 50 | 5 min |
| `smsMonth` | 250 | 30 days |
| `forcedSlowMode` | 1 | 30s |
| `instantMeeting` | 1 | 10 min |

### Selected Slots (Reservation System)
**Where:** `packages/features/di/modules/SelectedSlots.ts`
**How it works:** Selected slots (temporary booking reservations) use a `PrismaSelectedSlotRepository` bound via DI, not Redis. The repository is injected with the Prisma client.

**Example:**
```typescript
selectedSlotsRepositoryModule
  .bind(DI_TOKENS.SELECTED_SLOT_REPOSITORY)
  .toClass(PrismaSelectedSlotRepository, [DI_TOKENS.PRISMA_CLIENT]);
```

## Conventions

- Always access Redis through `getRedisService()` from the DI container, not by importing `RedisService` directly
- Cache failures (read or write) should never break application flow -- the decorators handle this automatically
- TTL is specified in milliseconds for the `@Memoize` decorator and `IRedisService.set()`
- The default TTL is 5 minutes (`DEFAULT_TTL_MS = 5 * 60 * 1000`)
- Rate limiting is separate from Redis caching and uses Unkey

## Dependencies

- `@upstash/redis` - Upstash Redis REST client
- `@unkey/ratelimit` - Rate limiting service
- Environment variables:
  - `UPSTASH_REDIS_REST_URL` - Redis REST endpoint
  - `UPSTASH_REDIS_REST_TOKEN` - Redis auth token
  - `UNKEY_ROOT_KEY` - Rate limiting API key

## Gotchas

- Redis is **optional** for the application to function. The `NoopRedisService` means all cache reads return `null` and writes are silently ignored
- The `RedisService` constructor throws if env vars are missing, but the DI module guards against this
- The `@Memoize` decorator validates cached data with an optional Zod schema -- if validation fails, it re-fetches from the source
- Rate limiting returns success even without `UNKEY_ROOT_KEY` -- it just logs a warning once
- The Redis client uses a 2-second timeout via `AbortSignal.timeout(2000)` to prevent slow Redis from blocking requests
- Selected slots use Prisma/database, not Redis

## Related Concepts

- [Dependency Injection](./dependency-injection.md) - Redis is wired through the DI system
- [Feature Architecture](./feature-architecture.md) - Feature flags use the `@Memoize` decorator
