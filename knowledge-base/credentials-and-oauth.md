# Credentials and OAuth

> Credentials are stored in the database with optional AES-256-GCM encryption via a keyring system. OAuth flows use a centralized `OAuthManager` for token lifecycle management.

## Overview

Cal.com stores third-party app credentials in the `Credential` Prisma model. The `key` field holds the raw JSON token data, while `encryptedKey` holds an encrypted envelope. Credentials can be user-owned, team-owned, or delegation credentials (shared org-level credentials). The OAuth flow for third-party apps follows a standard authorization code grant, with callbacks handled per-app in the app store.

## Key Locations

| Path | Purpose |
|------|---------|
| `packages/lib/crypto/keyring.ts` | AES-256-GCM encryption/decryption using keyring env vars |
| `packages/features/credentials/services/CredentialDataService.ts` | Builds credential data with encryption |
| `packages/features/credentials/services/CredentialAccessService.ts` | Authorization checks for credential access |
| `packages/features/credentials/repositories/CredentialRepository.ts` | Data access layer for credentials |
| `packages/features/credentials/handleDeleteCredential.ts` | Credential deletion with cascading cleanup |
| `packages/app-store/_utils/oauth/OAuthManager.ts` | OAuth2 token lifecycle manager |
| `packages/app-store/_utils/oauth/createOAuthAppCredential.ts` | Creates credential after OAuth callback |
| `packages/app-store/_utils/oauth/refreshOAuthTokens.ts` | Token refresh utilities |
| `packages/lib/delegationCredential.ts` | Delegation credential helpers |
| `packages/prisma/selects/credential.ts` | Safe Prisma select objects (excludes `key`) |

## Patterns

### Credential Encryption via Keyring
**Where:** `packages/lib/crypto/keyring.ts`
**How it works:** Uses AES-256-GCM with env-based key management. Keys are stored in env vars like `CALCOM_KEYRING_CREDENTIALS_K1` (base64url-encoded 32-byte keys). The current key is identified by `CALCOM_KEYRING_CREDENTIALS_CURRENT`. The encryption produces a `SecretEnvelopeV1` containing version, algorithm, key ID, nonce, ciphertext, and auth tag.

**Example:**
```typescript
import { encryptSecret, decryptSecret } from "@calcom/lib/crypto/keyring";

// Encrypt
const envelope = encryptSecret({
  ring: "CREDENTIALS",
  plaintext: JSON.stringify(tokenData),
  aad: { type: "google_calendar" },  // Additional authenticated data
});

// Decrypt
const plaintext = decryptSecret({
  envelope,
  aad: { type: "google_calendar" },
});
```

### Building Credential Data with Encryption
**Where:** `packages/features/credentials/services/CredentialDataService.ts`
**How it works:** `buildCredentialCreateData` wraps credential creation, adding the `encryptedKey` field. If the keyring is not configured, `encryptedKey` is null for backwards compatibility.

**Example:**
```typescript
import { buildCredentialCreateData } from "@calcom/features/credentials/services/CredentialDataService";

const data = buildCredentialCreateData({
  type: "google_calendar",
  key: tokenObject,
  userId: 123,
  appId: "google-calendar",
});
// data.encryptedKey is now populated (or null if keyring not configured)
```

### OAuth Callback Flow
**Where:** `packages/app-store/stripepayment/api/callback.ts` (example for Stripe)
**How it works:** After the OAuth provider redirects back, the callback handler exchanges the authorization code for tokens, then stores them as a credential. The `createOAuthAppCredential` utility handles user-vs-team credential creation based on state.

**Example:**
```typescript
// 1. User clicks "Connect" -> redirected to provider OAuth page
// 2. Provider redirects back to /api/integrations/<app>/callback
// 3. Callback handler:
const response = await stripe.oauth.token({ grant_type: "authorization_code", code });
await createOAuthAppCredential(
  { appId: "stripe", type: "stripe_payment" },
  data,
  req  // req.session determines userId, state may contain teamId
);
```

### OAuthManager Token Lifecycle
**Where:** `packages/app-store/_utils/oauth/OAuthManager.ts`
**How it works:** The `OAuthManager` class manages the full OAuth2 token lifecycle including automatic refresh, credential sync from third parties, and token invalidation. It wraps API requests and automatically handles expired/invalid tokens.

**Key behaviors:**
- Auto-refreshes tokens 5 seconds before expiry
- Supports credential sync from external sources
- Categorizes responses into `VALID`, `UNUSABLE_TOKEN_OBJECT`, `UNUSABLE_ACCESS_TOKEN`, or `INCONCLUSIVE`
- Falls back to credential sync endpoint when refresh fails (self-hosted scenarios)

**Example usage pattern:**
```typescript
const oAuthManager = new OAuthManager({
  appSlug: "google-calendar",
  resourceOwner: { id: userId, type: "user" },
  currentTokenObject: parsedToken,
  fetchNewTokenObject: ({ refreshToken }) => { /* refresh logic */ },
  updateTokenObject: async (token) => { /* save to DB */ },
  isTokenObjectUnusable: async (response) => { /* check if refresh_token revoked */ },
  isAccessTokenUnusable: async (response) => { /* check 401s */ },
  invalidateTokenObject: async () => { /* mark credential as invalid */ },
  expireAccessToken: async () => { /* mark access token expired */ },
  credentialSyncVariables: { /* env vars for credential sync */ },
});

const { json } = await oAuthManager.request({ url, options });
```

### Credential Access Control
**Where:** `packages/features/credentials/services/CredentialAccessService.ts`
**How it works:** Before accessing a credential, the service checks ownership: direct user ownership, booking owner ownership, or team membership access (including organization).

**Example:**
```typescript
const accessService = new CredentialAccessService(prisma);
await accessService.ensureAccessible({
  credentialId: 42,
  loggedInUserId: currentUser.id,
  bookingOwnerId: booking.userId,
});
// Throws 403 if not accessible, 404 if not found
```

### Delegation Credentials
**Where:** `packages/lib/delegationCredential.ts`, `packages/features/credentials/repositories/CredentialRepository.ts`
**How it works:** Delegation credentials allow organization-level credentials to be shared with members. A `DelegationCredential` model exists in the database, and per-user credentials reference it via `delegationCredentialId`. In-memory delegation credentials use negative IDs (e.g., -1).

**Key functions:**
- `isInMemoryDelegationCredential({ credentialId })` - checks if credential ID is negative
- `buildNonDelegationCredential(credential)` - strips delegation fields, returns null for in-DB delegation credentials
- `CredentialRepository.createDelegationCredential()` - creates a user credential linked to a delegation credential

### Credential Deletion with Cleanup
**Where:** `packages/features/credentials/handleDeleteCredential.ts`
**How it works:** Deleting a credential cascades to: replacing video locations with Cal Video, removing destination calendars, removing CRM metadata, hiding event types with removed payment apps, cancelling unpaid bookings, cleaning up Zapier/Make webhooks, and resetting default conferencing app.

## Conventions

- The `key` field is considered sensitive; use `safeCredentialSelect` (from `packages/prisma/selects/credential.ts`) to exclude it from queries
- Include `key` only when explicitly needed (e.g., for API calls to the third party)
- Credentials belong to either a user (`userId`) or a team (`teamId`), never both
- The `type` field follows the pattern `<app_slug>_<category>` (e.g., `stripe_payment`, `google_calendar`)
- The `appId` field matches the app slug in the app store

## Dependencies

- `@calcom/prisma` - Database access for Credential model
- Node.js `crypto` module - AES-256-GCM encryption
- Environment variables: `CALCOM_KEYRING_CREDENTIALS_CURRENT`, `CALCOM_KEYRING_CREDENTIALS_K1` (or other key IDs)
- Legacy: `CALENDSO_ENCRYPTION_KEY` (still referenced in Docker/deployment configs)

## Gotchas

- If keyring env vars are not configured, `encryptedKey` will be `null` -- this is expected in dev/test environments
- The `buildNonDelegationCredential` function returns `null` for in-DB delegation user credentials, which can cause unexpected null values
- `OAuthManager` requires either `currentTokenObject` or `getCurrentTokenObject` to be provided
- When credential sync is enabled, tokens get a 1-year pseudo-expiry instead of immediate expiry
- The AAD (Additional Authenticated Data) in encryption must match exactly between encrypt and decrypt calls

## Related Concepts

- [App Store Integrations](./app-store-integrations.md) - Each app defines its OAuth add/callback handlers
- [Payments and Stripe](./payments-and-stripe.md) - Stripe uses OAuth Connect for credential setup
- [Dependency Injection](./dependency-injection.md) - CredentialRepository is registered in DI
