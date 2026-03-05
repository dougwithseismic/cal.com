# Next.js Routing

> How App Router and Pages Router coexist in Cal.com, route group conventions, and page types.

## Overview

Cal.com's web app (`apps/web`) is migrating from Next.js Pages Router to App Router. The App Router uses route groups to separate booking pages (public) from dashboard pages (authenticated). Some legacy pages remain in `pages/`. API routes exist in both routers.

## Key Locations

| Path | Purpose |
|------|---------|
| `apps/web/app/` | App Router root |
| `apps/web/app/layout.tsx` | Root layout (fonts, providers, i18n) |
| `apps/web/app/(booking-page-wrapper)/` | Public booking pages |
| `apps/web/app/(use-page-wrapper)/` | Authenticated dashboard pages |
| `apps/web/app/(use-page-wrapper)/(main-nav)/` | Dashboard pages with main navigation |
| `apps/web/app/api/` | API routes (App Router) |
| `apps/web/app/_trpc/` | tRPC client setup for App Router |
| `apps/web/pages/` | Legacy Pages Router (migration in progress) |
| `apps/web/pages/api/` | Legacy API routes |

## Patterns

### Route Groups

#### `(booking-page-wrapper)` -- Public Booking Pages
**Where:** `apps/web/app/(booking-page-wrapper)/`
**How it works:** Wraps public booking pages with a minimal page wrapper (no auth required, `isBookingPage=true`).
**Example:**
```tsx
// apps/web/app/(booking-page-wrapper)/layout.tsx
export default async function BookingPageWrapperLayout({ children }) {
  const h = await headers();
  const nonce = h.get("x-csp-nonce") ?? undefined;
  return (
    <PageWrapper isBookingPage={true} requiresLicense={false} nonce={nonce}>
      {children}
    </PageWrapper>
  );
}
```

Routes under this group:
```
(booking-page-wrapper)/
  [user]/              # User booking pages (/:username)
    [type]/            # Event type pages (/:username/:eventSlug)
    embed/             # Embedded booking pages
    page.tsx           # User profile page
  booking/             # Booking management (reschedule, cancel)
  booking-successful/  # Post-booking success page
  d/                   # Dynamic group bookings
  org/                 # Organization booking pages
  team/                # Team booking pages
```

#### `(use-page-wrapper)` -- Dashboard Pages
**Where:** `apps/web/app/(use-page-wrapper)/`
**How it works:** Wraps authenticated dashboard pages with the full page wrapper (session, navigation, scripts).
**Example:**
```tsx
// apps/web/app/(use-page-wrapper)/layout.tsx
export default async function PageWrapperLayout({ children }) {
  const h = await headers();
  const nonce = h.get("x-csp-nonce") ?? undefined;
  return (
    <PageWrapper requiresLicense={false} nonce={nonce}>
      {children}
    </PageWrapper>
  );
}
```

Routes under this group:
```
(use-page-wrapper)/
  (main-nav)/          # Pages with main sidebar navigation
    availability/      # Availability settings
    booking/           # Booking details
    bookings/          # Bookings list
    event-types/       # Event type management
    members/           # Team members
    teams/             # Team management
  apps/                # App store / integrations
  auth/                # Authentication pages
  connect-and-join/    # Meeting join page
  enterprise/          # Enterprise features
  getting-started/     # Onboarding
  insights/            # Analytics dashboard
  maintenance/         # Maintenance mode
  more/                # More options
  onboarding/          # Onboarding flow
  payment/             # Payment pages
  settings/            # User/team settings
  signup/              # Registration
  upgrade/             # Plan upgrade
  video/               # Video call pages
  workflow/            # Single workflow
  workflows/           # Workflow list
```

### Root Layout
**Where:** `apps/web/app/layout.tsx`
**How it works:** Server component that sets up fonts (Inter + Cal Sans), i18n provider, theme providers, and global CSS.
**Example:**
```tsx
// apps/web/app/layout.tsx:1-8
import { getLocale } from "@calcom/features/auth/lib/getLocale";
import { loadTranslations } from "@calcom/i18n/server";
import { IconSprites } from "@calcom/ui/components/icon";
import { dir } from "i18next";
import { Inter } from "next/font/google";
import localFont from "next/font/local";
```

### tRPC in App Router
**Where:** `apps/web/app/_trpc/`
**How it works:** Contains the tRPC client, provider, query client, and context setup for the App Router.

| File | Purpose |
|------|---------|
| `trpc.ts` | tRPC client configuration |
| `trpc-client.ts` | Client-side tRPC setup |
| `trpc-provider.tsx` | React context provider |
| `query-client.ts` | React Query client |
| `context.ts` | Server-side context |

### API Routes
**Where:** `apps/web/app/api/`, `apps/web/pages/api/`
**How it works:** API routes exist in both App Router and Pages Router. Key API endpoints:

| Route | Purpose |
|-------|---------|
| `app/api/auth/` | Authentication (NextAuth) |
| `app/api/cron/` | Scheduled tasks |
| `app/api/webhook/` | Webhook handlers |
| `app/api/availability/` | Availability endpoints |
| `app/api/video/` | Video call endpoints |
| `pages/api/book/` | Booking creation endpoint |
| `pages/api/trpc/` | tRPC API handler |

### Legacy Pages Router
**Where:** `apps/web/pages/`
**How it works:** Some pages remain in the Pages Router during migration. The router directory handles catch-all routes.
```
pages/
  _app.tsx       # Pages Router app wrapper
  _document.tsx  # Custom document
  _error.tsx     # Error page
  api/           # Legacy API routes
  router/        # Dynamic route handling
```

### Server vs Client Components
**How it works:**
- **Layouts** are server components (access headers, cookies, do server-side data loading)
- **Page wrappers** use `"use client"` for interactive features
- **Data fetching** happens client-side via tRPC hooks (SSR is disabled: `ssr: false`)
- **Booker** component is explicitly `"use client"` (Zustand store requires it)

### Special App Router Files
**Where:** `apps/web/app/`

| File | Purpose |
|------|---------|
| `error.tsx` | Error boundary |
| `global-error.tsx` | Global error handler |
| `not-found.tsx` | 404 page |
| `page.tsx` | Root page |
| `providers.tsx` | Client providers (theme, session, etc.) |
| `AppRouterI18nProvider.tsx` | i18n context for App Router |
| `WithAppDirSsr.tsx` | SSR helper for App Router pages |
| `WithEmbedSSR.tsx` | Embed SSR wrapper |
| `GeoContext.tsx` | Geolocation context |

## Conventions

- Route groups use parentheses: `(booking-page-wrapper)`, `(use-page-wrapper)`, `(main-nav)`
- Public routes go in `(booking-page-wrapper)`, authenticated routes in `(use-page-wrapper)`
- Dashboard pages with sidebar nav go in `(main-nav)` nested within `(use-page-wrapper)`
- API routes are gradually moving from `pages/api/` to `app/api/`
- Each route group has its own `layout.tsx` with the appropriate wrapper
- CSP nonce is extracted from headers in layouts

## Dependencies

- **Framework:** Next.js (App Router + Pages Router)
- **Auth:** NextAuth.js
- **i18n:** i18next with server-side loading
- **Fonts:** Inter (Google), Cal Sans (local)

## Gotchas

- SSR is disabled for tRPC (`ssr: false` in trpc config) -- all data fetching is client-side
- The booking creation endpoint is still in Pages Router (`pages/api/book/event`)
- The `router/` directory in `pages/` handles catch-all routing for legacy URLs
- `PageWrapper` component exists in both App Router and Pages Router versions
- The `(main-nav)` route group has its own `ShellMainAppDir.tsx` for the sidebar shell
- `reschedule/` and `routing-forms/` are at the app root level, not inside route groups

## Related Concepts

- [React Hooks](./react-hooks.md) -- hooks used in page components
- [tRPC Routers](./trpc-routers.md) -- API layer consumed by pages
- [UI Components](./ui-components.md) -- shared components used in pages
- [Booking Flow](./booking-flow.md) -- booking page routes
