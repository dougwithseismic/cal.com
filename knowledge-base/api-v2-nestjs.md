# API v2 (NestJS)

> Cal.com's API v2 is a NestJS application at `apps/api/v2/` that serves versioned REST endpoints for bookings, event types, schedules, and platform operations, with multi-method authentication, rate limiting, and Redis-backed caching.

## Overview

API v2 replaces the Next.js pages-based API v1 with a structured NestJS application. It uses modules for domain separation, Passport strategies for authentication, NestJS guards for authorization, and connects to the same Prisma database and shared packages as the web app. The API supports versioned endpoints (e.g., `2024-04-15`, `2024-08-13`) and serves both direct API consumers (via API keys) and platform clients (via OAuth).

## Key Locations

| Path | Purpose |
|------|---------|
| `apps/api/v2/src/app.module.ts` | Root NestJS module with global config, Redis, throttling, Prisma |
| `apps/api/v2/src/modules/endpoints.module.ts` | Aggregates all endpoint modules |
| `apps/api/v2/src/modules/auth/auth.module.ts` | Auth module with Passport strategies and guards |
| `apps/api/v2/src/modules/auth/strategies/api-auth/api-auth.strategy.ts` | Multi-method authentication strategy |
| `apps/api/v2/src/modules/auth/guards/` | Guard implementations (roles, permissions, org, team) |
| `apps/api/v2/src/modules/auth/decorators/` | Custom decorators for auth, roles, permissions |
| `apps/api/v2/src/modules/auth/oauth2/` | OAuth2 token endpoint and authorize flow |
| `apps/api/v2/src/modules/oauth-clients/` | Platform OAuth client CRUD and flow management |
| `apps/api/v2/src/modules/prisma/prisma.module.ts` | Prisma module (shared DB access) |
| `apps/api/v2/src/modules/redis/redis.module.ts` | Redis module for caching and rate limiting |
| `apps/api/v2/src/ee/` | Enterprise features (bookings, calendars, event-types, schedules) |
| `apps/api/v2/src/lib/` | Shared utilities, booking modules, OAuth modules |
| `apps/api/v2/src/modules/organizations/` | Organization-scoped endpoints |
| `apps/api/v2/src/modules/teams/` | Team-scoped endpoints |

## Patterns

### Root Module Configuration
**Where:** `apps/api/v2/src/app.module.ts`
**How it works:** The `AppModule` imports global modules (Config, Redis, BullMQ, Throttler, Prisma, Auth, JWT) and registers global providers (Sentry filter, response interceptor, rate limiter). Middleware is configured with specific body parsers per route -- raw body for billing webhooks, URL-encoded for OAuth token endpoint, JSON for everything else.
**Example:**
```typescript
@Module({
  imports: [
    SentryModule.forRoot(),
    ConfigModule.forRoot({ ignoreEnvFile: true, isGlobal: true, load: [appConfig] }),
    RedisModule,
    BullModule.forRoot({ redis: `${process.env.REDIS_URL}...` }),
    ThrottlerModule.forRootAsync({
      imports: [RedisModule],
      inject: [RedisService],
      useFactory: (redisService: RedisService) => ({
        throttlers: [{ name: "dummy", ttl: seconds(60), limit: 120 }],
        storage: new ThrottlerStorageRedisService(redisService.redis),
      }),
    }),
    PrismaModule, EndpointsModule, AuthModule, JwtModule,
  ],
  providers: [
    { provide: APP_FILTER, useClass: SentryGlobalFilter },
    { provide: APP_INTERCEPTOR, useClass: ResponseInterceptor },
    { provide: APP_GUARD, useClass: CustomThrottlerGuard },
  ],
})
export class AppModule implements NestModule { ... }
```

### Module Organization
**Where:** `apps/api/v2/src/modules/endpoints.module.ts`
**How it works:** The `EndpointsModule` imports all feature modules. Enterprise features live under `apps/api/v2/src/ee/` with a `PlatformEndpointsModule`. Versioned modules use date-based naming (e.g., `EventTypesModule_2024_06_14`, `BookingsModule_2024_08_13`).
**Example modules:**
- `OAuth2Module` -- OAuth2 token exchange
- `OAuthClientModule` -- Platform client management (global module)
- `BillingModule` -- Stripe billing
- `AtomsModule` -- Platform atom endpoints
- `OrganizationsBookingsModule`, `TeamsBookingsModule` -- scoped booking endpoints

### Controller Pattern
**Where:** `apps/api/v2/src/modules/auth/oauth2/controllers/oauth2.controller.ts`
**How it works:** Controllers use NestJS decorators for versioning, Swagger docs, guards, and validation. The `API_VERSIONS_VALUES` array enables all supported versions on every controller. Guards are applied per-endpoint with `@UseGuards()`.
**Example:**
```typescript
@Controller({ path: "/v2/auth/oauth2", version: API_VERSIONS_VALUES })
@ApiTags("OAuth2")
export class OAuth2Controller {
  @Post("/token")
  @HttpCode(HttpStatus.OK)
  @UseFilters(OAuth2HttpExceptionFilter)
  @Header("Cache-Control", "no-store")
  async token(@Body(new OAuth2TokenInputPipe()) body: OAuth2TokenInput): Promise<OAuth2TokensDto> {
    const tokens = await this.oAuthService.handleTokenRequest(body.client_id, body);
    return plainToInstance(OAuth2TokensDto, tokens, { strategy: "excludeAll" });
  }
}
```

### Guard and Interceptor Patterns
**Where:** `apps/api/v2/src/modules/auth/guards/`
**How it works:** Guards are layered and composable:

1. **`ApiAuthGuard`** -- Passport-based, delegates to `ApiAuthStrategy`. Reads `@ApiAuthGuardOnlyAllow` decorator to restrict auth methods.
2. **`RolesGuard`** -- Checks org/team membership roles with Redis caching (5min TTL). Uses `@Roles()` decorator.
3. **`PermissionsGuard`** -- Checks platform OAuth client bitfield permissions. Uses `@Permissions()` decorator.
4. **`OrGuard`** -- Combines multiple guards with OR logic (any guard passing means access is granted).
5. **Org/Team guards** -- `IsOrgGuard`, `IsTeamInOrgGuard`, `IsUserInOrgGuard`, etc.

**Example:**
```typescript
export class ApiAuthGuard extends AuthGuard("api-auth") {
  getRequest(context: ExecutionContext) {
    const request = context.switchToHttp().getRequest();
    const allowedMethods = this.reflector.get(ApiAuthGuardOnlyAllow, context.getHandler());
    request.allowedAuthMethods = allowedMethods;
    return request;
  }
}
```

### Custom Decorators
**Where:** `apps/api/v2/src/modules/auth/decorators/`
**How it works:** Decorators extract data from requests or set metadata for guards:
- `@GetUser()` -- extracts authenticated user from request
- `@GetOrg()` / `@GetOrgId()` -- extracts organization from params
- `@GetTeam()` -- extracts team from params
- `@GetMembership()` -- extracts membership info
- `@Roles("ORG_ADMIN")` -- sets minimum role for `RolesGuard`
- `@Permissions(BOOKING_READ)` -- sets required permissions for `PermissionsGuard`
- `@PlatformPlan("ESSENTIALS")` -- gates by billing plan
- `@ApiAuthGuardOnlyAllow("API_KEY", "ACCESS_TOKEN")` -- restricts auth methods

### Connecting to Shared Packages
**Where:** Various modules
**How it works:** API v2 imports from shared monorepo packages:
- `@calcom/prisma` -- Database access via `PrismaModule`
- `@calcom/platform-constants` -- API constants, header names, version strings
- `@calcom/platform-types` -- Input/output DTOs
- `@calcom/platform-utils` -- Permission checking (`hasPermissions`)
- `@calcom/features/` -- Shared business logic (credentials, organizations, webhooks)

The `PrismaModule` wraps the shared Prisma client in a NestJS-injectable service. The `OAuthClientModule` is marked `@Global()` so OAuth client lookup is available everywhere.

### Platform OAuth Client System
**Where:** `apps/api/v2/src/modules/oauth-clients/`
**How it works:** Platform customers create OAuth clients via `OAuthClientsController`. Each client has an `id`, `secret`, `redirectUris`, `permissions` (bitfield), and belongs to an organization. The OAuth flow supports both confidential (client_secret) and public (PKCE with code_verifier) clients. Token exchange happens at `/v2/auth/oauth2/token`.

Key components:
- `OAuthClientRepository` -- Prisma queries for client CRUD
- `OAuthFlowService` -- Validates access tokens, manages refresh flow
- `OAuthFlowController` -- Handles authorize redirect and callback
- `TokensRepository` -- Manages access/refresh token storage

### Difference from API v1

| Aspect | API v1 | API v2 |
|--------|--------|--------|
| Framework | Next.js API Routes | NestJS |
| Location | `apps/api/v1/pages/api/` | `apps/api/v2/src/` |
| Auth | API key query param only | API key, OAuth, access token, NextAuth |
| Middleware | `next-api-middleware` pipeline | NestJS guards, interceptors, pipes |
| Validation | Zod schemas per endpoint | Class-validator DTOs with pipes |
| Versioning | None | Date-based versions (e.g., `2024-08-13`) |
| Structure | File-based routing (`_get.ts`, `_post.ts`) | Module/Controller/Service pattern |
| Rate Limiting | Per-key rate limiter | Redis-backed `ThrottlerModule` |

## Conventions

- API versions follow date format: `VERSION_2024_06_14`, `VERSION_2024_08_13`, etc.
- Enterprise modules live under `apps/api/v2/src/ee/`
- All responses use `{ status: "success", data: ... }` shape via `ResponseInterceptor`
- OAuth headers: `x-cal-client-id` and `x-cal-secret-key` for platform client credentials
- Version header: `cal-api-version` for specifying API version
- Module imports use `@/` path alias for `apps/api/v2/src/`
- `plainToInstance` with `{ strategy: "excludeAll" }` is used to strip sensitive fields from responses

## Dependencies

- `@nestjs/core`, `@nestjs/common`, `@nestjs/config` -- NestJS framework
- `@nestjs/passport` -- Passport authentication integration
- `@nestjs/bull` -- BullMQ job queue (Redis-backed)
- `@nestjs/throttler` -- Rate limiting with Redis storage
- `@sentry/nestjs` -- Error tracking
- `@calcom/prisma` -- Shared Prisma client
- `@calcom/platform-constants` -- API constants and header names
- `next-auth/jwt` -- Token verification for NextAuth fallback auth

## Gotchas

- The `ThrottlerModule` requires at least one "dummy" throttler entry for the `CustomThrottlerGuard` to be invoked -- actual rate limits are configured in the guard itself.
- The billing webhook route requires raw body parsing (not JSON), configured explicitly in `AppModule.configure()`.
- The `OAuthClientModule` is `@Global()`, making `OAuthClientRepository` available everywhere without explicit imports.
- Role check results are cached in Redis for 300 seconds -- membership changes have a delayed effect.
- The `PermissionsGuard` only applies to platform access tokens, not API keys or NextAuth sessions.

## Related Concepts

- [Authentication and Authorization](./authentication-and-authorization.md) -- auth strategies and guards in detail
- [Platform SDK and Atoms](./platform-sdk-atoms.md) -- how platform clients use API v2
