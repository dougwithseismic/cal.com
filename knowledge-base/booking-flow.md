# Booking Flow

> End-to-end architecture of how bookings are created, from slot selection to calendar event creation.

## Overview

The booking flow spans multiple packages: slots are computed server-side via tRPC, the Booker UI component manages the user-facing booking experience with Zustand state, booking creation goes through a REST API endpoint that delegates to service classes, and calendar integrations create events on external calendars. Different scheduling types (round-robin, collective, managed) affect host selection.

## Key Locations

| Path | Purpose |
|------|---------|
| `packages/trpc/server/routers/viewer/slots/` | Slot availability computation (tRPC) |
| `packages/features/bookings/Booker/` | Booker UI component, store, hooks |
| `packages/features/bookings/Booker/store.ts` | Zustand store for booking state |
| `packages/features/bookings/Booker/hooks/` | Hooks for time slots, form, layout |
| `packages/features/bookings/lib/` | Core booking logic (creation, cancellation, rescheduling) |
| `packages/features/bookings/lib/create-booking.ts` | Client-side booking creation (POST to /api/book/event) |
| `packages/features/bookings/lib/handleNewBooking/` | Server-side new booking handler |
| `packages/features/bookings/lib/service/RegularBookingService.ts` | DI-based booking service (newer pattern) |
| `packages/features/bookings/lib/EventManager.ts` | Calendar/video event orchestration |
| `packages/features/bookings/lib/handleCancelBooking/` | Cancellation logic |
| `packages/features/bookings/repositories/` | Data access for bookings |
| `packages/features/bookings/di/` | Dependency injection for booking services |
| `packages/features/availability/lib/` | Availability computation logic |
| `packages/features/slots/` | Slot notification handling |

## Patterns

### 1. Slot Computation
**Where:** `packages/trpc/server/routers/viewer/slots/_router.tsx`
**How it works:** The `getSchedule` public procedure computes available time slots. It accepts event slug, username, date range, and timezone. The handler delegates to `AvailableSlotsService`.
**Example:**
```ts
// packages/trpc/server/routers/viewer/slots/_router.tsx:17-25
export const slotsRouter = router({
  getSchedule: publicProcedure.input(ZGetScheduleInputSchema).query(async ({ input, ctx }) => {
    const { getScheduleHandler } = await import("./getSchedule.handler");
    return getScheduleHandler({ ctx, input });
  }),
  reserveSlot: publicProcedure.input(ZReserveSlotInputSchema).mutation(async ({ input, ctx }) => {
    const { reserveSlotHandler } = await import("./reserveSlot.handler");
    return reserveSlotHandler({ ctx, input });
  }),
});
```

### 2. Booker UI Component
**Where:** `packages/features/bookings/Booker/`
**How it works:** The Booker is a React component using Zustand for state management. It supports multiple layouts (month view, week view, column view) and tracks the booking flow state machine (selecting date -> selecting time -> filling form -> confirming).

Key store state:
```ts
// packages/features/bookings/Booker/store.ts (StoreInitializeType)
type StoreInitializeType = {
  username: string;
  eventSlug: string;
  eventId: number | undefined;
  layout: BookerLayout;
  month?: string;
  bookingUid?: string | null;
  rescheduleUid?: string | null;
  timezone?: string | null;
  isInstantMeeting?: boolean;
  // ...
};
```

The Booker directory structure:
- `store.ts` -- Zustand store (booking state, date, timezone, layout)
- `BookerStoreProvider.tsx` -- React context for store
- `hooks/useAvailableTimeSlots.ts` -- transforms schedule response to calendar format
- `hooks/useBookerTime.ts` -- timezone resolution
- `hooks/useBookingForm.ts` -- react-hook-form setup with Zod validation
- `hooks/useBookerLayout.ts` -- responsive layout management
- `components/` -- UI sub-components
- `config.ts` -- layout configuration

### 3. Client-Side Booking Creation
**Where:** `packages/features/bookings/lib/create-booking.ts`
**How it works:** The client sends a POST to `/api/book/event` with booking data.
**Example:**
```ts
// packages/features/bookings/lib/create-booking.ts:5-14
export const createBooking = async (data: BookingCreateBody) => {
  const response = await post<BookingCreateBody, ...>("/api/book/event", data);
  return response;
};
```

### 4. Server-Side Booking Handler
**Where:** `packages/features/bookings/lib/handleNewBooking/`
**How it works:** The handler pipeline processes a new booking through multiple steps:

| File | Purpose |
|------|---------|
| `getBookingData.ts` | Parse and validate incoming booking data |
| `getEventType.ts` | Load event type configuration |
| `getEventTypesFromDB.ts` | Database query for event type with all relations |
| `loadUsers.ts` | Load and validate available users/hosts |
| `ensureAvailableUsers.ts` | Check user availability |
| `createBooking.ts` | Create the Booking record in Prisma |
| `checkBookingAndDurationLimits.ts` | Enforce booking/duration limits |
| `checkActiveBookingsLimitForBooker.ts` | Per-booker active booking limits |
| `getVideoCallDetails.ts` | Set up video conferencing |
| `handleAppsStatus.ts` | Process calendar/app integrations |
| `scheduleNoShowTriggers.ts` | Schedule no-show webhooks |

### 5. RegularBookingService (DI Pattern)
**Where:** `packages/features/bookings/lib/service/RegularBookingService.ts`
**How it works:** The newer DI-based service handles booking creation with injected dependencies. Uses `@evyweb/ioctopus` for dependency injection.
**Example:**
```ts
// packages/features/bookings/di/RegularBookingService.module.ts:18-36
const loadModule = bindModuleToClassOnToken({
  module: thisModule,
  moduleToken,
  token,
  classs: RegularBookingService,
  depsMap: {
    prismaClient: prismaModuleLoader,
    checkBookingAndDurationLimitsService: checkBookingAndDurationLimitsModuleLoader,
    bookingRepository: bookingRepositoryModuleLoader,
    luckyUserService: luckyUserServiceModuleLoader,
    userRepository: userRepositoryModuleLoader,
    hashedLinkService: hashedLinkServiceModuleLoader,
    bookingEmailAndSmsTasker: bookingEmailAndSmsTaskerModuleLoader,
    bookingEventHandler: bookingEventHandlerModuleLoader,
    webhookProducer: webhookProducerModuleLoader,
  },
});
```

Container access:
```ts
// packages/features/bookings/di/RegularBookingService.container.ts
export function getRegularBookingService(): RegularBookingService {
  regularBookingServiceModule.loadModule(regularBookingServiceContainer);
  return regularBookingServiceContainer.get<RegularBookingService>(regularBookingServiceModule.token);
}
```

### 6. EventManager (Calendar Integration)
**Where:** `packages/features/bookings/lib/EventManager.ts`
**How it works:** Orchestrates creating/updating/deleting events across calendar and video conferencing integrations. Iterates over connected calendar credentials and creates events on each.

### 7. Scheduling Types
**Where:** `packages/prisma/schema.prisma:42-46`
**How it works:**

| Type | Behavior |
|------|----------|
| `ROUND_ROBIN` | Rotates among hosts; uses "lucky user" algorithm with weights and priority |
| `COLLECTIVE` | All hosts must be available; single event for all |
| `MANAGED` | Parent event type creates child event types for each team member |

Round-robin host selection: `packages/features/bookings/lib/getLuckyUser.ts`

## Conventions

- Booking creation always goes through `/api/book/event` (REST), not tRPC
- Slot computation goes through tRPC (`trpc.viewer.slots.getSchedule`)
- The Booker component is the single entry point for all booking UIs (web, embed, platform atoms)
- Booking state machine: `idle -> selecting_date -> selecting_time -> booking_form -> booking`
- All booking-related hooks are colocated in `packages/features/bookings/Booker/hooks/`

## Dependencies

- **UI:** Zustand, react-hook-form, @calcom/dayjs
- **Backend:** Prisma, EventManager, app-store calendar/video services
- **DI:** @evyweb/ioctopus

## Gotchas

- There are two booking creation paths: the legacy `handleNewBooking/` functions and the newer `RegularBookingService` -- both may be in use
- Instant meetings have a separate service (`InstantBookingCreateService`)
- Recurring bookings have their own service (`RecurringBookingService`)
- The `reserveSlot` mutation temporarily holds a slot to prevent double-booking
- Booking cancellation is in `packages/features/bookings/lib/handleCancelBooking/` and also has a DI service

## Related Concepts

- [tRPC Routers](./trpc-routers.md) -- slot and booking queries
- [App Store Integrations](./app-store-integrations.md) -- calendar services
- [Prisma and Database](./prisma-and-database.md) -- Booking model
- [Feature Architecture](./feature-architecture.md) -- DI pattern for services
