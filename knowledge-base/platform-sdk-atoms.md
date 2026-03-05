# Platform SDK and Atoms

> Cal.com's Platform SDK provides publishable React components ("atoms") and hooks that allow third-party developers to embed scheduling functionality (booker, availability, calendar settings, event types) into their own applications, authenticated via OAuth against API v2.

## Overview

The Platform SDK is a collection of packages under `packages/platform/` that enable external developers to build white-label scheduling products using Cal.com's infrastructure. The `@calcom/atoms` package exports React components that render cal.com UI (booker, schedules, calendars) while communicating with the API v2 backend. Platform clients authenticate via OAuth (client_id + secret or PKCE), manage users ("managed users"), and have bitfield-based permissions controlling what resources they can access.

## Key Locations

| Path | Purpose |
|------|---------|
| `packages/platform/atoms/` | Published npm package with React components and hooks |
| `packages/platform/atoms/index.ts` | Main export file for all atoms and hooks |
| `packages/platform/atoms/booker/BookerPlatformWrapper.tsx` | Platform-aware Booker component |
| `packages/platform/atoms/src/components/atoms-wrapper.tsx` | Wrapper providing platform context to atoms |
| `packages/platform/atoms/hooks/` | React hooks for bookings, event types, calendars, etc. |
| `packages/platform/atoms/cal-provider/` | `CalProvider` and `CalOAuthProvider` context providers |
| `packages/platform/constants/` | API constants, header names, permissions |
| `packages/platform/constants/api.ts` | API versions, status codes, header constants |
| `packages/platform/constants/permissions.ts` | Bitfield permission definitions |
| `packages/platform/enums/` | Shared enums for the platform |
| `packages/platform/types/` | TypeScript types and DTOs |
| `packages/platform/libraries/` | Shared library utilities |
| `packages/platform/utils/` | Utility functions (permission checking) |
| `apps/api/v2/src/modules/oauth-clients/` | Server-side OAuth client management |
| `apps/api/v2/src/modules/atoms/atoms.module.ts` | API v2 atoms endpoint module |
| `apps/api/v2/src/modules/auth/guards/permissions/permissions.guard.ts` | Permission enforcement for platform clients |

## Patterns

### Atoms Package Architecture
**Where:** `packages/platform/atoms/index.ts`
**How it works:** The atoms package exports ready-to-use React components and hooks. Components are "platform wrappers" that detect whether they are running in platform context (via `useIsPlatform`) and use platform-specific API hooks accordingly. The package is published to npm as `@calcom/atoms`.

**Exported components:**
```typescript
export { BookerPlatformWrapper as Booker } from "./booker/BookerPlatformWrapper";
export { BookerEmbed } from "./booker-embed";
export { CalOAuthProvider, CalProvider } from "./cal-provider";
export { AvailabilitySettingsPlatformWrapper as AvailabilitySettings } from "./availability";
export { CalendarSettingsPlatformWrapper as CalendarSettings } from "./calendar-settings";
export { CalendarViewPlatformWrapper as CalendarView } from "./calendar-view";
export { ListEventTypesPlatformWrapper as ListEventTypes } from "./event-types";
export { CreateEventTypePlatformWrapper as CreateEventType } from "./event-types/wrappers/CreateEventTypePlatformWrapper";
export { EventTypePlatformWrapper as EventTypeSettings } from "./event-types/wrappers/EventTypePlatformWrapper";
export { DestinationCalendarSettingsPlatformWrapper as DestinationCalendarSettings } from "./destination-calendar";
export { CreateSchedulePlatformWrapper as CreateSchedule } from "./create-schedule";
export { ListSchedulesPlatformWrapper as ListSchedules } from "./list-schedules";
export { SelectedCalendarsSettingsPlatformWrapper as SelectedCalendarsSettings } from "./selected-calendars";
export { TroubleshooterPlatformWrapper as TroubleShooter } from "./troubleshooter";
export { Router } from "./router";
```

**Exported hooks:**
```typescript
export { useBooking } from "./hooks/bookings/useBooking";
export { useBookings } from "./hooks/bookings/useBookings";
export { useCancelBooking } from "./hooks/bookings/useCancelBooking";
export { useEventTypes } from "./hooks/event-types/public/useEventTypes";
export { useAvailableSlots } from "./hooks/useAvailableSlots";
export { useConnectedCalendars } from "./hooks/useConnectedCalendars";
export { useMe } from "./hooks/useMe";
export { useIsPlatform } from "./hooks/useIsPlatform";
```

### BookerPlatformWrapper
**Where:** `packages/platform/atoms/booker/BookerPlatformWrapper.tsx`
**How it works:** Wraps the core `Booker` component from `@calcom/web/modules/bookings/components/Booker` with platform-specific hook replacements. It uses platform hooks (`useCreateBooking`, `useAvailableSlots`, `useHandleBookEvent`) instead of the web app's tRPC-based hooks. It reads the `clientId` from `useAtomsContext()` to identify the platform context.
**Example:**
```typescript
const BookerPlatformWrapperComponent = (props) => {
  const { clientId } = useAtomsContext();
  const teamId = props.isTeamEvent ? props.teamId : undefined;
  // Uses platform-specific hooks for booking, slots, etc.
  const { data: event } = useAtomGetPublicEvent({ username, eventSlug, ... });
  const slots = useAvailableSlots({ eventTypeId, ... });
  return <BookerComponent {...} />;
};
```

### CalProvider and CalOAuthProvider
**Where:** `packages/platform/atoms/cal-provider/`
**How it works:** `CalProvider` wraps the app in a React context that provides the platform client ID and access token. `CalOAuthProvider` additionally handles the OAuth flow. All atoms read the `clientId` from this context via `useAtomsContext()`.

### Platform Constants
**Where:** `packages/platform/constants/api.ts`
**How it works:** Defines all API-level constants used by both the atoms (client) and API v2 (server):
```typescript
export const X_CAL_SECRET_KEY = "x-cal-secret-key";
export const X_CAL_CLIENT_ID = "x-cal-client-id";
export const X_CAL_PLATFORM_EMBED = "x-cal-platform-embed";
export const SUCCESS_STATUS = "success";
export const ERROR_STATUS = "error";
export const CAL_API_VERSION_HEADER = "cal-api-version";
export const API_VERSIONS = ["2024-06-14", "2024-06-11", "2024-04-15", "2024-08-13", "2024-09-04"];
```

### Permission System (Bitfield)
**Where:** `packages/platform/constants/permissions.ts`
**How it works:** Permissions are defined as powers of 2, allowing bitwise operations. Each OAuth client has a numeric `permissions` field. The `hasPermissions` utility from `@calcom/platform-utils` checks if a client's bitmask includes required permissions.
**Example:**
```typescript
export const EVENT_TYPE_READ = 1;   // 2^0
export const EVENT_TYPE_WRITE = 2;  // 2^1
export const BOOKING_READ = 4;      // 2^2
export const BOOKING_WRITE = 8;     // 2^3
export const SCHEDULE_READ = 16;    // 2^4
export const SCHEDULE_WRITE = 32;   // 2^5
export const APPS_READ = 64;       // 2^6
export const APPS_WRITE = 128;     // 2^7
export const PROFILE_READ = 256;   // 2^8
export const PROFILE_WRITE = 512;  // 2^9

export const PERMISSIONS_GROUPED_MAP = {
  EVENT_TYPE: { read: EVENT_TYPE_READ, write: EVENT_TYPE_WRITE, key: "eventType", label: "Event Type" },
  BOOKING: { read: BOOKING_READ, write: BOOKING_WRITE, key: "booking", label: "Booking" },
  // ...
};
```

### OAuth Client Management (Server-Side)
**Where:** `apps/api/v2/src/modules/oauth-clients/oauth-client.module.ts`
**How it works:** The `OAuthClientModule` is a `@Global()` NestJS module that provides OAuth client CRUD operations. It exposes three controllers:
- `OAuthClientsController` -- Create/update/delete OAuth clients (for org admins)
- `OAuthClientUsersController` -- Manage "managed users" under an OAuth client
- `OAuthFlowController` -- Handle authorize/callback flow

The module imports `AuthModule`, `BillingModule`, `UsersModule`, `TokensModule` and provides services for calendars, credentials, profiles, and Stripe integration.

### How API v2 Serves Platform Clients
**Where:** `apps/api/v2/src/modules/auth/strategies/api-auth/api-auth.strategy.ts`
**How it works:** Platform clients authenticate in two ways:
1. **OAuth client credentials** (server-to-server): Send `x-cal-client-id` + `x-cal-secret-key` headers. The strategy validates the secret, finds the platform org owner, and acts on their behalf.
2. **Access tokens** (user-facing): After OAuth authorization, the user gets an access token. The strategy validates it, checks origin against `redirectUris`, and identifies the user.

The `PermissionsGuard` then checks the client's bitfield permissions against the required permissions for the endpoint.

### Build and Publishing
**Where:** `packages/platform/atoms/package.json`
**How it works:** The atoms package is built with Vite and published to npm as `@calcom/atoms`. It exports both ESM (`dist/cal-atoms.js`) and UMD (`dist/cal-atoms.umd.cjs`) formats. CSS is separately published as `globals.min.css` built with PostCSS/Tailwind.
```json
{
  "name": "@calcom/atoms",
  "version": "2.3.3",
  "module": "./dist/cal-atoms.js",
  "main": "./dist/cal-atoms.umd.cjs",
  "peerDependencies": {
    "react": "^18.0.0 || ^19.0.0",
    "react-dom": "^18.0.0 || ^19.0.0"
  }
}
```

## Conventions

- All exported components use the `PlatformWrapper` suffix internally but are exported with clean names (e.g., `BookerPlatformWrapper` exported as `Booker`)
- Hooks follow the `use{Resource}` pattern (e.g., `useBookings`, `useAvailableSlots`)
- Platform detection uses `useIsPlatform()` hook which checks for `clientId` in context
- `@tanstack/react-query` is used for data fetching in platform hooks
- The `AtomsWrapper` component wraps each atom to provide necessary context

## Dependencies

- `react`, `react-dom` -- Peer dependencies
- `@tanstack/react-query` -- Data fetching and caching
- `@calcom/i18n` -- Internationalization
- `@radix-ui/react-*` -- UI primitives (dialog, popover, tooltip, switch, toast)
- `tailwindcss` -- Styling
- `vite` -- Build tool

## Gotchas

- The atoms package imports from `@calcom/web/modules/bookings/components/Booker` -- this creates a tight coupling with the web app's internal components.
- Platform atoms use different API hooks than the web app (REST via `@tanstack/react-query` instead of tRPC).
- The `globals.min.css` file must be imported by consumers to get proper styling.
- The `useIsPlatformBookerEmbed` hook exists separately from `useIsPlatform` for embed-specific detection.
- OAuth client permissions are checked at the guard level, not within individual service methods.

## Related Concepts

- [API v2 NestJS](./api-v2-nestjs.md) -- the backend that atoms communicate with
- [Authentication and Authorization](./authentication-and-authorization.md) -- OAuth flow and permission system
- [Embed System](./embed-system.md) -- alternative approach to embedding (iframe vs React components)
