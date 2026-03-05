# App Store Integrations

> How the Cal.com app store works, app structure conventions, and how to add new integrations.

## Overview

The Cal.com app store (`packages/app-store/`) houses 70+ third-party integrations including calendars (Google, Outlook, Apple), video conferencing (Zoom, Google Meet, Daily), CRMs (Close.com, HubSpot, Salesforce), payment processors (Stripe, PayPal), and analytics tools. Each app follows a standardized directory structure, and a CLI tool generates registry files.

## Key Locations

| Path | Purpose |
|------|---------|
| `packages/app-store/` | All integration apps |
| `packages/app-store/<app>/config.json` | App metadata (name, slug, type, category, variant) |
| `packages/app-store/<app>/_metadata.ts` | Runtime metadata with environment checks |
| `packages/app-store/<app>/lib/` | Integration logic (CalendarService, CrmService) |
| `packages/app-store/<app>/api/` | API routes (webhooks, OAuth callbacks) |
| `packages/app-store/<app>/components/` | Setup/config UI components |
| `packages/app-store/<app>/zod.ts` | Credential Zod schemas |
| `packages/app-store/<app>/index.ts` | App entry point |
| `packages/app-store-cli/` | CLI for app scaffolding and code generation |
| `packages/app-store/_lib/` | Shared utilities (CRM enums, schemas) |
| `packages/app-store/_utils/` | Shared utilities (OAuth, payments, calendars) |
| `packages/app-store/_components/` | Shared UI components |
| `packages/app-store/apps.metadata.generated.ts` | Generated app metadata registry |
| `packages/app-store/apps.server.generated.ts` | Generated server-side registry |
| `packages/app-store/calendar.services.generated.ts` | Generated calendar service map |
| `packages/app-store/crm.apps.generated.ts` | Generated CRM app registry |

## Patterns

### App Directory Structure
**Where:** `packages/app-store/<appname>/`
**How it works:** Each app is a self-contained package with a standardized structure.

Example (Google Calendar):
```
packages/app-store/googlecalendar/
  _metadata.ts        # Runtime metadata
  api/                # OAuth callback, webhook handlers
  index.ts            # Entry point
  lib/
    CalendarService.ts  # Calendar API implementation
    CalendarAuth.ts     # OAuth token management
    getGoogleAppKeys.ts
    googleCredentialSchema.ts
  package.json
  static/             # Icons, images
  tests/
  zod.ts              # Credential schema
```

### config.json
**Where:** `packages/app-store/<app>/config.json`
**How it works:** Declares app metadata used by the app store registry.
**Example:**
```json
// packages/app-store/closecom/config.json
{
  "name": "Close.com",
  "slug": "closecom",
  "type": "closecom_crm",
  "variant": "crm",
  "categories": ["crm"],
  "publisher": "Cal.com, Inc.",
  "extendsFeature": "EventType",
  "isOAuth": true,
  "dirName": "closecom"
}
```

Key fields:
- `slug` -- unique identifier (do not modify after creation)
- `type` -- format: `<slug>_<variant>` (e.g., `google_calendar`, `closecom_crm`)
- `variant` -- one of: `calendar`, `conferencing`, `crm`, `payment`, `analytics`, `other`
- `categories` -- array of categories for filtering
- `extendsFeature` -- what this app extends (e.g., `EventType`)

### _metadata.ts
**Where:** `packages/app-store/<app>/_metadata.ts`
**How it works:** Exports runtime metadata including `installed` status based on environment variables.
**Example:**
```ts
// packages/app-store/googlecalendar/_metadata.ts:5-21
export const metadata = {
  name: "Google Calendar",
  installed: !!(process.env.GOOGLE_API_CREDENTIALS && validJson(process.env.GOOGLE_API_CREDENTIALS)),
  type: "google_calendar",
  variant: "calendar",
  category: "calendar",
  categories: ["calendar"],
  slug: "google-calendar",
  dirName: "googlecalendar",
  isOAuth: true,
} as AppMeta;
```

### Calendar Service Pattern
**Where:** `packages/app-store/<calendar-app>/lib/CalendarService.ts`
**How it works:** Calendar apps implement the `Calendar` interface from `@calcom/types/Calendar`. Methods include `createEvent`, `updateEvent`, `deleteEvent`, `getAvailability`, and `listCalendars`.
**Example:**
```ts
// packages/app-store/googlecalendar/lib/CalendarService.ts:54-56
export interface GoogleCalendar extends Calendar {
  getPrimaryCalendar(...): Promise<...>;
  upsertSelectedCalendar(...): Promise<...>;
}
```

### CRM Service Pattern
**Where:** `packages/app-store/<crm-app>/lib/CrmService.ts`
**How it works:** CRM apps implement the `CRM` interface from `@calcom/types/CrmService`. Methods handle contact creation and event tracking.
**Example:**
```ts
// packages/app-store/closecom/lib/CrmService.ts:1-10
import type { CRM, ContactCreateInput, CrmEvent, Contact } from "@calcom/types/CrmService";
```

### Generated Files
**Where:** Root of `packages/app-store/`
**How it works:** The `packages/app-store-cli` generates registry files that aggregate all apps. These are auto-generated and should not be manually edited.

| Generated File | Purpose |
|----------------|---------|
| `apps.metadata.generated.ts` | All app metadata objects |
| `apps.server.generated.ts` | Server-side app loading |
| `apps.browser.generated.tsx` | Browser-side app components |
| `apps.keys-schemas.generated.ts` | Key/credential schemas |
| `apps.schemas.generated.ts` | App-specific schemas |
| `calendar.services.generated.ts` | Calendar service factory map |
| `analytics.services.generated.ts` | Analytics service factory map |
| `crm.apps.generated.ts` | CRM app registry |
| `bookerApps.metadata.generated.ts` | Booker-specific app metadata |

### Adding a New Integration
**How it works:**
1. Run `yarn create-app` (uses app-store CLI)
2. Fill in the prompts (name, slug, category, etc.)
3. Implement the service class in `lib/` (e.g., `CalendarService.ts` for calendars)
4. Add API routes in `api/` for OAuth callbacks
5. Add UI components in `components/` for setup
6. The CLI regenerates registry files automatically

CLI commands:
```bash
yarn create-app          # Create new app
yarn edit-app            # Edit existing app
yarn delete-app          # Delete an app
yarn app-store-cli watch # Watch for changes and regenerate
```

### Delegation Credentials
**Where:** `packages/app-store/delegationCredential.ts`
**How it works:** Some apps (Google Calendar, Google Meet) support domain-wide delegation, where a service account acts on behalf of users. The `delegationCredential` field in metadata indicates support.

## Conventions

- App directories use the app's `dirName` from config.json (no dashes, lowercase)
- Each app has its own `package.json`
- Generated files have `.generated.ts` or `.generated.tsx` suffix
- `config.json` slug should never change after creation
- Static assets (icons) go in `static/`
- Tests go in `tests/` within the app directory
- OAuth apps set `isOAuth: true` in config
- Credential schemas are in `zod.ts`

## Dependencies

- **Types:** `@calcom/types/Calendar`, `@calcom/types/CrmService`, `@calcom/types/Credential`
- **Used by:** EventManager (`packages/features/bookings/lib/EventManager.ts`), booking flow
- **CLI:** `packages/app-store-cli` (generates registry)

## Gotchas

- Do not manually edit files ending in `.generated.ts` -- they are overwritten by the CLI
- The `type` field in config.json must follow the `<dirName>_<variant>` convention
- Environment variables for each app are listed in `.env.appStore.example`
- Some apps check `process.env.*` in `_metadata.ts` to determine `installed` status
- The `_appRegistry.ts` file is the main app lookup mechanism
- CRM and calendar shared utilities are in `packages/app-store/_lib/` and `_utils/`

## Related Concepts

- [Booking Flow](./booking-flow.md) -- calendar services are called during booking creation
- [Monorepo and Tooling](./monorepo-and-tooling.md) -- app-store CLI commands
- [Feature Architecture](./feature-architecture.md) -- CRM manager in features
