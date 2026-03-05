# Authentication and Authorization

> Cal.com uses NextAuth.js for web app authentication, API key hashing for API v1, and a multi-strategy Passport system in API v2 (NestJS) supporting OAuth, API keys, access tokens, and NextAuth sessions.

## Overview

Authentication in cal.com is split across three contexts: the Next.js web app (NextAuth), API v1 (API key middleware), and API v2 (NestJS guards + Passport strategies). Authorization uses a mix of role-based checks (system admin, org roles, team roles) and bitfield permissions for platform OAuth clients.

## Key Locations

| Path | Purpose |
|------|---------|
| `packages/features/auth/lib/next-auth-options.ts` | Main NextAuth configuration (providers, callbacks, adapter) |
| `packages/features/auth/lib/next-auth-custom-adapter.ts` | Custom Prisma adapter for NextAuth |
| `packages/features/auth/lib/getServerSession.ts` | Slimmed-down server session retrieval with LRU cache |
| `packages/features/auth/lib/getSession.ts` | Client-side session wrapper around `next-auth/react` |
| `packages/features/auth/lib/ensureSession.ts` | Throws 401 if no valid session exists |
| `packages/features/auth/lib/oAuthAuthorization.ts` | OAuth token verification for API v1-style OAuth |
| `packages/features/auth/lib/signJwt.ts` | Signs short-lived JWTs with `jose` using `CALENDSO_ENCRYPTION_KEY` |
| `packages/features/auth/lib/samlAccountLinking.ts` | SAML IdP authority validation to prevent account takeover |
| `packages/features/auth/lib/verifyPassword.ts` | bcrypt password verification |
| `packages/features/auth/PermissionContainer.tsx` | React component gating UI by user role |
| `packages/features/auth/signup/` | Signup handlers, username validation, org membership creation |
| `packages/lib/auth/hashPassword.ts` | Password hashing utility |
| `packages/lib/auth/isPasswordValid.ts` | Password strength validation |
| `apps/api/v1/lib/helpers/verifyApiKey.ts` | API v1 key verification middleware |
| `apps/api/v1/lib/helpers/withMiddleware.ts` | API v1 middleware pipeline |
| `apps/api/v2/src/modules/auth/auth.module.ts` | API v2 NestJS auth module |
| `apps/api/v2/src/modules/auth/strategies/api-auth/api-auth.strategy.ts` | API v2 multi-method authentication strategy |
| `apps/api/v2/src/modules/auth/guards/api-auth/api-auth.guard.ts` | API v2 Passport guard |
| `apps/api/v2/src/modules/auth/guards/roles/roles.guard.ts` | API v2 role-based authorization guard |
| `apps/api/v2/src/modules/auth/guards/permissions/permissions.guard.ts` | API v2 platform permission guard (bitfield) |

## Patterns

### NextAuth Provider Configuration
**Where:** `packages/features/auth/lib/next-auth-options.ts`
**How it works:** NextAuth is configured with three providers: `CredentialsProvider` (email/password), `EmailProvider` (magic link), and `GoogleProvider` (OAuth login). An `ImpersonationProvider` is also included for admin impersonation. The `GOOGLE_LOGIN_ENABLED` flag controls whether Google sign-in is active.
**Example:**
```typescript
const IS_GOOGLE_LOGIN_ENABLED = !!(GOOGLE_CLIENT_ID && GOOGLE_CLIENT_SECRET && GOOGLE_LOGIN_ENABLED);
```

### Custom NextAuth Adapter
**Where:** `packages/features/auth/lib/next-auth-custom-adapter.ts`
**How it works:** A custom `CalComAdapter` wraps Prisma calls and handles the id type conversion (NextAuth uses strings, cal.com uses numeric IDs). It includes a legacy fallback for users who signed up with Google/SAML before the `Account` table existed, looking them up via `identityProvider` + `identityProviderId`.
**Example:**
```typescript
export default function CalComAdapter(prismaClient: PrismaClient): Adapter {
  return {
    createUser: async (data) => {
      const user = await prismaClient.user.create({ data: createUserData(data) });
      return toAdapterUser(user);
    },
    // Session methods are no-ops since JWT strategy is used
    createSession: async (session) => session,
    getSessionAndUser: async () => null,
  } satisfies Adapter;
}
```

### Server Session with LRU Cache
**Where:** `packages/features/auth/lib/getServerSession.ts`
**How it works:** Instead of calling NextAuth's full `getServerSession`, this custom version extracts the JWT token via `getToken()`, fetches the user from the DB, enriches it with profile data, and caches the result in an LRU cache (max 1000 entries) keyed by stringified token. This avoids repeated DB lookups within the same request lifecycle.
**Example:**
```typescript
const CACHE = new LRUCache<string, Session>({ max: 1000 });

export async function getServerSession(options: {
  req: NextApiRequest | GetServerSidePropsContext["req"];
  authOptions?: AuthOptions;
}) {
  const token = await getToken({ req, secret });
  if (!token || !token.email || !token.sub) return null;
  const cachedSession = CACHE.get(JSON.stringify(token));
  if (cachedSession) return cachedSession;
  // ... fetch user, build session, cache it
}
```

### API v1 Authentication (Middleware Pipeline)
**Where:** `apps/api/v1/lib/helpers/verifyApiKey.ts`
**How it works:** API v1 uses `next-api-middleware` with a labeled pipeline. The `verifyApiKey` middleware strips the prefix (default `cal_`), hashes the key with SHA256, looks it up in the DB, checks expiration, and attaches `req.userId`. Additional checks determine admin scope (`SystemWide` vs `OrgOwnerOrAdmin`).
**Example:**
```typescript
const middlewareOrder: Middleware[] = [
  "extendRequest",
  "captureErrors",
  "verifyApiKey",
  "rateLimitApiKey",
  "addRequestId",
  "captureUserId",
];
```

### API v2 Multi-Strategy Authentication
**Where:** `apps/api/v2/src/modules/auth/strategies/api-auth/api-auth.strategy.ts`
**How it works:** The `ApiAuthStrategy` extends a Passport `BaseStrategy` and supports five authentication methods, tried in order: (1) OAuth client credentials via `x-cal-client-id` + `x-cal-secret-key` headers, (2) API key as Bearer token (detected by `cal_` prefix), (3) Platform access token as Bearer, (4) Third-party access tokens, (5) NextAuth JWT cookie fallback. A controller can restrict allowed methods via the `@ApiAuthGuardOnlyAllow` decorator.
**Example:**
```typescript
if (oAuthClientId && oAuthClientSecret && oAuthAllowed) {
  request.authMethod = AuthMethods["OAUTH_CLIENT"];
  return await this.authenticateOAuthClient(oAuthClientId, oAuthClientSecret, request);
}
if (bearerToken) {
  request.authMethod = isApiKey(bearerToken, "cal_")
    ? AuthMethods["API_KEY"]
    : AuthMethods["ACCESS_TOKEN"];
  return await this.authenticateBearerToken(bearerToken, request, requestOrigin);
}
```

### Role-Based Authorization (API v2)
**Where:** `apps/api/v2/src/modules/auth/guards/roles/roles.guard.ts`
**How it works:** The `RolesGuard` checks user membership roles against required roles using ordered role arrays (`ORG_ROLES`, `TEAM_ROLES`). System admins bypass all checks. Results are cached in Redis for 5 minutes. Org admins/owners automatically satisfy team role requirements.
**Example:**
```typescript
if (user.isSystemAdmin) { canAccess = true; }
else if (Boolean(orgId) && !Boolean(teamId)) {
  const membership = await this.membershipRepository.findMembershipByOrgId(Number(orgId), user.id);
  canAccess = hasMinimumRole({
    checkRole: `ORG_${membership.role}`,
    minimumRole: allowedRole,
    roles: ORG_ROLES,
  });
}
```

### Platform Permission Guard (Bitfield)
**Where:** `apps/api/v2/src/modules/auth/guards/permissions/permissions.guard.ts`
**How it works:** Platform OAuth clients have a numeric `permissions` field where each bit represents a scope (e.g., `EVENT_TYPE_READ = 1`, `BOOKING_WRITE = 8`). The `PermissionsGuard` extracts required permissions from the `@Permissions()` decorator and checks them against the client's bitmask using `hasPermissions()`. NextAuth sessions, API keys, and third-party tokens skip this check entirely.

### SAML/SSO Account Linking
**Where:** `packages/features/auth/lib/samlAccountLinking.ts`
**How it works:** The `SamlAccountLinkingService` validates whether a SAML IdP is authoritative for a given email, preventing malicious IdPs from taking over accounts. Authority is established if the email domain matches verified org domains or the user has an existing membership. On hosted Cal.com, tenant must be in `team-{id}` format; self-hosted allows non-org tenants.

### UI Permission Gating
**Where:** `packages/features/auth/PermissionContainer.tsx`
**How it works:** A React component that reads the NextAuth session and renders children only if the user has the required role (defaults to `ADMIN`). ADMIN users always pass.
**Example:**
```tsx
export const PermissionContainer: FC<AdminRequiredProps> = ({ children, roleRequired = "ADMIN" }) => {
  const session = useSession();
  if (session.data?.user.role !== roleRequired && session.data?.user.role != UserPermissionRole.ADMIN)
    return null;
  return <>{children}</>;
};
```

## Conventions

- NextAuth uses JWT strategy (not database sessions) -- session DB methods in the adapter are no-ops
- API keys are prefixed with `cal_` (configurable via `API_KEY_PREFIX` env var), stripped before SHA256 hashing
- The `CALENDSO_ENCRYPTION_KEY` environment variable is used for JWT signing and symmetric encryption
- Impersonation is tracked via `token.impersonatedBy` in the JWT payload
- License key validation is checked in both API v1 and API v2 auth flows
- User profiles are enriched with organization data via `UserRepository.enrichUserWithTheProfile()`

## Dependencies

- `next-auth` -- core authentication framework for the web app
- `@nestjs/passport` -- Passport integration for API v2
- `jose` -- JWT signing for short-lived tokens
- `bcryptjs` -- password hashing
- `lru-cache` -- server session caching
- `@calcom/prisma` -- database access for user/account/token lookups

## Gotchas

- The custom `getServerSession` does NOT refresh expired tokens (30-day expiry). Client-side calls to `/auth/session` keep sessions alive.
- API v2 origin validation only applies to access tokens (not API keys or OAuth client credentials). The origin must match one of the OAuth client's `redirectUris`.
- The `RolesGuard` caches role check results in Redis for 300 seconds. Role changes may take up to 5 minutes to take effect in API v2.
- Google login requires both `GOOGLE_API_CREDENTIALS` JSON and `GOOGLE_LOGIN_ENABLED=true` to be set.

## Related Concepts

- [API v2 NestJS](./api-v2-nestjs.md) -- the NestJS application that uses these guards
- [Platform SDK and Atoms](./platform-sdk-atoms.md) -- platform OAuth clients and permissions
