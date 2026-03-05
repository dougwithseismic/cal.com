# React Hooks

> How custom and library hooks are used across the Cal.com codebase for state management, data fetching, and UI logic.

## Overview

Cal.com uses React hooks extensively across `packages/features/`, `packages/ui/`, and `apps/web/`. Custom hooks handle booking state (Zustand stores), schedule computation, form validation (react-hook-form + Zod), and permission checks. tRPC hooks provide typed data fetching throughout the frontend.

## Key Locations

| Path | Purpose |
|------|---------|
| `packages/features/bookings/Booker/hooks/` | Booker UI hooks (time slots, layout, forms) |
| `packages/features/bookings/hooks/` | General booking hooks (URL, location, week start) |
| `packages/features/schedules/hooks/` | Schedule time computation |
| `packages/features/flags/hooks/` | Feature flag hooks |
| `packages/features/pbac/client/hooks/` | Permission-based access control hooks |
| `packages/features/embed/lib/hooks/` | Embed-related hooks |
| `packages/features/ee/managed-event-types/hooks/` | Locked field management |
| `packages/features/ee/workflows/hooks/` | Workflow voice preview |
| `packages/trpc/react/trpc.ts` | tRPC React hook setup (`createTRPCNext`) |
| `packages/trpc/components/QueryCell.tsx` | Query state wrapper component |
| `packages/lib/hooks/` | Shared utility hooks (`useLocale`, etc.) |

## Patterns

### Zustand Store Hooks (Booker)
**Where:** `packages/features/bookings/Booker/store.ts`
**How it works:** The Booker uses Zustand for client-side state management. A store is created with `createWithEqualityFn` and holds booking state (selected date, timezone, layout, booker state machine, reschedule data). Components consume slices via selectors.
**Example:**
```ts
// packages/features/bookings/Booker/store.ts:1-3
"use client";
import { useEffect } from "react";
import { createWithEqualityFn } from "zustand/traditional";
```
Components use the store via a context provider:
```ts
// packages/features/bookings/Booker/hooks/useBookerTime.ts:6-7
const [timezoneFromBookerStore] = useBookerStoreContext((state) => [state.timezone], shallow);
const { timezone: timezoneFromTimePreferences, timeFormat } = useTimePreferences();
```

### tRPC Hooks (Data Fetching)
**Where:** `apps/web/` components
**How it works:** The `trpc` object is created via `createTRPCNext` in `packages/trpc/react/trpc.ts`. Frontend components call `trpc.viewer.<domain>.<procedure>.useQuery()` or `.useMutation()`. The router path maps to `packages/trpc/server/routers/viewer/`.
**Example:**
```tsx
// apps/web/components/ui/UsernameAvailability/PremiumTextfield.tsx:71,76
const [user] = trpc.viewer.me.get.useSuspenseQuery();
const { data: stripeCustomer } = trpc.viewer.loggedInViewerRouter.stripeCustomer.useQuery();
```
```tsx
// apps/web/modules/webhooks/views/webhook-new-view.tsx:33
const createWebhookMutation = trpc.viewer.webhook.create.useMutation({...});
```

### QueryCell Pattern
**Where:** `packages/trpc/components/QueryCell.tsx`
**How it works:** A wrapper component that handles loading/error/success/empty states for tRPC queries. Takes a `query` result and renders appropriate state.
**Example:**
```tsx
// packages/trpc/components/QueryCell.tsx:19-26
interface QueryCellOptionsBase<TData, TError extends ErrorLike> {
  query: UseQueryResult<TData, TError>;
  customLoader?: ReactNode;
  error?: (...) => JSXElementOrNull;
  loading?: (...) => JSXElementOrNull;
}
```

### react-hook-form + Zod Validation
**Where:** `packages/features/bookings/Booker/hooks/useBookingForm.ts`
**How it works:** Forms use `useForm` from react-hook-form with `zodResolver` for schema-driven validation. The booking form schema is built dynamically from event type booking fields.
**Example:**
```ts
// packages/features/bookings/Booker/hooks/useBookingForm.ts:1-4
import { zodResolver } from "@hookform/resolvers/zod";
import { useRef, useEffect } from "react";
import { useForm } from "react-hook-form";
import { z } from "zod";
```
```ts
// packages/features/bookings/Booker/hooks/useBookingForm.ts:45-56
const bookingFormSchema = z
  .object({
    responses: event
      ? getBookingResponsesSchema({
          bookingFields: event.bookingFields,
          view: rescheduleUid ? "reschedule" : "booking",
          translateFn: (key, options) => t(key, options ?? {}),
        })
      : z.object({}),
  })
  .passthrough();
```

### Schedule/Time Hooks
**Where:** `packages/features/schedules/hooks/useTimesForSchedule.ts`
**How it works:** Computes start/end time ranges for slot queries based on the current month, selected date, day count, and booker layout. Handles prefetching of next months.
**Example:**
```ts
// packages/features/schedules/hooks/useTimesForSchedule.ts:87-95
export const useTimesForSchedule = ({ month, selectedDate, dayCount, bookerLayout }) => {
  const [monthFromStore, bookerState] = useBookerStoreContext(
    (state) => [state.month, state.state], shallow
  );
  // ... computes startTime, endTime
  return [startTime, endTime];
};
```

### Available Time Slots Hook
**Where:** `packages/features/bookings/Booker/hooks/useAvailableTimeSlots.ts`
**How it works:** Transforms the schedule API response (keyed by date string) into `CalendarAvailableTimeslots` format with proper `Date` objects.
**Example:**
```ts
// packages/features/bookings/Booker/hooks/useAvailableTimeSlots.ts:31-48
export const useAvailableTimeSlots = ({ schedule, eventDuration }) => {
  return useMemo(() => {
    const availableTimeslots = {};
    if (!schedule || !schedule.slots) return availableTimeslots;
    for (const day in schedule.slots) {
      availableTimeslots[day] = schedule.slots[day].map((slot) => ({
        start: dayjs(slot.time).toDate(),
        end: dayjs(slot.time).add(eventDuration, "minutes").toDate(),
        ...rest,
      }));
    }
    return availableTimeslots;
  }, [schedule, eventDuration]);
};
```

### Permission Hooks
**Where:** `packages/features/pbac/client/hooks/usePermission.ts`, `useEventPermission.ts`
**How it works:** Provides hooks for checking user permissions in the UI layer, integrating with the PBAC (Permission-Based Access Control) system.

## Conventions

- Custom hooks are placed in `hooks/` subdirectories within their feature package
- Zustand is the primary client-state library (not Redux)
- tRPC hooks follow the pattern: `trpc.viewer.<namespace>.<procedure>.useQuery|useMutation()`
- Form hooks combine react-hook-form with Zod schemas via `zodResolver`
- The `shallow` comparator from Zustand is used to prevent unnecessary re-renders
- `useMemo` is used for expensive transformations (e.g., slot computation)
- Hook files use camelCase prefixed with `use` (e.g., `useBookerTime.ts`)

## Dependencies

- **Uses:** `zustand`, `@trpc/react-query`, `react-hook-form`, `@hookform/resolvers/zod`, `zod`, `@calcom/dayjs`
- **Used by:** All React components in `apps/web/`, `packages/features/*/components/`, `packages/platform/atoms/`

## Gotchas

- tRPC endpoint routing splits paths to different lambda endpoints based on path segments (see `resolveEndpoint` in `packages/trpc/react/trpc.ts`)
- The Booker store uses a context provider (`BookerStoreProvider`) -- always access via `useBookerStoreContext`, not the raw store
- `useFormContext` requires wrapping in a `FormProvider` from react-hook-form
- Time-related hooks depend on `@calcom/dayjs` (a configured wrapper around dayjs)

## Related Concepts

- [tRPC Routers](./trpc-routers.md) -- backend that hooks call into
- [Booking Flow](./booking-flow.md) -- the Booker hooks are central to this
- [UI Components](./ui-components.md) -- form components that use these hooks
