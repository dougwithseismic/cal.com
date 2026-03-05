# Event Types

> The core bookable entity in cal.com, defining duration, scheduling rules, team assignment, and all booking configuration.

## Overview

An EventType is the central configuration object that defines how bookings work. It controls duration, scheduling windows, buffer times, locations, booking fields, recurring patterns, and team assignment. Event types can be personal (owned by a user), team-based (with round-robin, collective, or managed scheduling), or dynamically generated for group booking. The Prisma model has 80+ fields spanning scheduling, UI, and integration configuration.

## Key Locations

| Path | Purpose |
|------|---------|
| `packages/prisma/schema.prisma` (line ~156) | `EventType` Prisma model with all fields |
| `packages/prisma/schema.prisma` (line ~61) | `Host` model - links users to team event types |
| `packages/features/eventtypes/lib/types.ts` | `FormValues`, `EventTypeUpdateInput`, `Host` TypeScript types |
| `packages/features/eventtypes/lib/getEventTypeById.ts` | Fetches and enriches a single event type for the editor |
| `packages/features/eventtypes/lib/getEventTypesPublic.ts` | Public-facing event type queries |
| `packages/features/eventtypes/lib/getPublicEvent.ts` | Fetches event type data for the booking page |
| `packages/features/eventtypes/lib/defaultEvents.ts` | Default/dynamic event type template |
| `packages/features/eventtypes/lib/childrenEventType.ts` | `ChildrenEventType` type for managed events |
| `packages/features/eventtypes/lib/schemas.ts` | Zod schemas for create/duplicate inputs |
| `packages/features/eventtypes/service/EventTypeService.ts` | Branding logic service |
| `packages/features/eventtypes/repositories/eventTypeRepository.ts` | Database queries |
| `packages/features/eventtypes/components/tabs/limits/EventLimitsTab.tsx` | Limits UI (period, booking limits, buffers) |
| `packages/features/eventtypes/components/tabs/recurring/RecurringEventController.tsx` | Recurring event UI |
| `packages/trpc/server/routers/viewer/eventTypes/` | tRPC handlers for CRUD operations |

## Patterns

### Scheduling Types
**Where:** `packages/prisma/schema.prisma:42-46`
**How it works:** The `SchedulingType` enum defines three team scheduling modes:

```prisma
enum SchedulingType {
  ROUND_ROBIN @map("roundRobin")
  COLLECTIVE  @map("collective")
  MANAGED     @map("managed")
}
```

- **ROUND_ROBIN**: Bookings rotate among team hosts. Hosts have `priority` and `weight` for weighted assignment. Fixed hosts (`isFixed: true`) are always included; non-fixed hosts rotate.
- **COLLECTIVE**: All assigned hosts must be available. The booking is created with all hosts as attendees.
- **MANAGED**: A parent event type creates child event types for each assigned member. The parent acts as a template; children inherit settings but appear on individual profiles.

When `schedulingType` is `null`, the event type is a personal (non-team) event type.

### Host Assignment Model
**Where:** `packages/prisma/schema.prisma:61-81`
**How it works:** The `Host` join table connects users to team event types with scheduling metadata:

```prisma
model Host {
  userId      Int
  eventTypeId Int
  isFixed     Boolean   @default(false)
  priority    Int?
  weight      Int?
  scheduleId  Int?      // host-specific schedule override
  groupId     String?   // round-robin group assignment
  @@id([userId, eventTypeId])
}
```

- `isFixed`: In round-robin, fixed hosts appear on every booking; non-fixed hosts rotate
- `priority`: Lower values = higher priority in round-robin assignment
- `weight`: Relative booking weight for weighted round-robin
- `groupId`: Groups round-robin hosts so at least one from each group is selected
- `scheduleId`: Allows a host to use a different schedule for this specific event type

### Period Types (Scheduling Windows)
**Where:** `packages/prisma/schema.prisma:48-53`
**How it works:** Controls how far into the future bookings can be made:

```prisma
enum PeriodType {
  UNLIMITED      @map("unlimited")
  ROLLING        @map("rolling")
  ROLLING_WINDOW @map("rolling_window")
  RANGE          @map("range")
}
```

- **UNLIMITED**: No restriction on future booking dates
- **ROLLING**: Available for `periodDays` days from today. `periodCountCalendarDays` controls whether weekends count
- **ROLLING_WINDOW**: Like ROLLING but uses a window calculation
- **RANGE**: Available only between `periodStartDate` and `periodEndDate`

Configuration fields on EventType: `periodType`, `periodDays`, `periodCountCalendarDays`, `periodStartDate`, `periodEndDate`.

The `rollingExcludeUnavailableDays` form value controls whether unavailable days are excluded from the rolling count.

### Buffer Times
**Where:** `packages/prisma/schema.prisma:220-221`, `packages/features/eventtypes/lib/types.ts:158-159`
**How it works:** Two buffer fields create gaps around bookings:

- `beforeEventBuffer` (default 0): Minutes blocked before the event starts
- `afterEventBuffer` (default 0): Minutes blocked after the event ends

These buffers are included in busy time calculations by `getUserAvailability`, making adjacent time slots unavailable.

### Minimum Booking Notice
**Where:** `packages/prisma/schema.prisma:219`
**How it works:** `minimumBookingNotice` (default 120 minutes) prevents last-minute bookings. In slot computation, slots starting before `now + minimumBookingNotice` are excluded:

```typescript
// packages/features/schedules/lib/slots.ts:123
const startTimeWithMinNotice = dayjs.utc().add(minimumBookingNotice, "minute");
```

### Booking and Duration Limits
**Where:** `packages/prisma/schema.prisma:248-251`
**How it works:** `bookingLimits` and `durationLimits` are JSON fields using the `IntervalLimit` type. They define maximum bookings or total booked minutes per period (day, week, month, year). When limits are reached, the system generates synthetic busy times that block further slots.

```typescript
// packages/features/eventtypes/lib/types.ts:168-169
durationLimits?: IntervalLimit;
bookingLimits?: IntervalLimit;
```

### Recurring Events
**Where:** `packages/prisma/schema.prisma:214`
**How it works:** The `recurringEvent` JSON field stores recurrence rules (RFC 5545-like):

```typescript
// packages/features/eventtypes/lib/types.ts:299-306
export type RecurringEventInput = {
  dtstart?: Date;
  interval: number;   // e.g., every 2 weeks
  count: number;      // number of occurrences
  freq: number;       // frequency type (daily, weekly, monthly)
  until?: Date;
  tzid?: string;
} | null;
```

### Managed Event Types (Parent-Child)
**Where:** `packages/prisma/schema.prisma:190-192`
**How it works:** Managed event types use a self-referential relation:

```prisma
parentId Int?
parent   EventType? @relation("managed_eventtype", fields: [parentId], references: [id], onDelete: Cascade)
children EventType[] @relation("managed_eventtype")
```

The parent event type acts as a template. When updated, changes propagate to children. Each child belongs to an individual team member and appears on their profile. `ChildrenEventType` in `packages/features/eventtypes/lib/childrenEventType.ts` defines the shape:

```typescript
export type ChildrenEventType = {
  owner: {
    id: number;
    email: string;
    name: string;
    username: string;
    membership: MembershipRole;
    eventTypeSlugs: string[];
  };
  slug: string;
  hidden: boolean;
};
```

### Dynamic Group Booking
**Where:** `packages/features/eventtypes/lib/defaultEvents.ts`
**How it works:** Dynamic event types are generated on-the-fly for ad-hoc group bookings between multiple users. They use the `isDynamic: true` flag and share common defaults:

```typescript
const commons = {
  isDynamic: true,
  periodCountCalendarDays: true,
  periodType: PeriodType.UNLIMITED,
  beforeEventBuffer: 0,
  afterEventBuffer: 0,
  minimumBookingNotice: 120,
  locations: [{ type: DailyLocationType }],
  disableGuests: true,
};
```

### Seats Per Time Slot
**Where:** `packages/prisma/schema.prisma:222`
**How it works:** `seatsPerTimeSlot` enables seated events where multiple attendees can book the same time slot. Related fields:
- `seatsShowAttendees`: Whether attendees can see each other
- `seatsShowAvailabilityCount`: Whether remaining seat count is shown

### Slot Configuration
**Where:** `packages/features/eventtypes/lib/types.ts:160-161`
**How it works:**
- `slotInterval`: Override the gap between slot start times (defaults to event length)
- `offsetStart`: Shifts all slot start times by N minutes
- `onlyShowFirstAvailableSlot`: Shows just one slot per day
- `showOptimizedSlots`: Maximizes slot count by not rounding to hour boundaries

### Event Type Form Values
**Where:** `packages/features/eventtypes/lib/types.ts:97-198`
**How it works:** The `FormValues` type defines every field the event type editor form can submit. It includes scheduling config, UI settings, team assignment, booking fields, and integrations. The `EventTypeUpdateInput` type (line ~342) mirrors this for the tRPC update mutation.

### Event Type Service Architecture
**Where:** `packages/features/eventtypes/service/EventTypeService.ts`
**How it works:** Uses constructor injection with an `EventTypeRepository`:

```typescript
export class EventTypeService {
  constructor(private eventTypeRepository: EventTypeRepository) {}
  async shouldHideBrandingForEventType(eventTypeId: number, prefetchedData?: EventTypeBrandingData): Promise<boolean>
}
```

DI container is at `packages/features/eventtypes/di/EventTypeService.container.ts`.

### Event Type Retrieval
**Where:** `packages/features/eventtypes/lib/getEventTypeById.ts:37-45`
**How it works:** `getEventTypeById()` fetches raw event type data, parses metadata with `eventTypeMetaDataSchemaWithTypedApps`, enriches user profiles, resolves locations, parses recurring events and limits, and resolves the booker URL based on organization context.

## Conventions

- Event types are uniquely constrained by `[userId, slug]` or `[teamId, slug]`
- `price` and `currency` on EventType are deprecated; now stored in `metadata.apps.stripe`
- Metadata is a JSON field parsed with `EventTypeMetaDataSchema` from `packages/prisma/zod-utils`
- `bookingFields` is a JSON field holding custom form field definitions
- The `Host.weightAdjustment` field is deprecated; calibration is now computed on the fly
- `locations` is a JSON field with typed location objects (video, phone, in-person, etc.)

## Dependencies

- `@calcom/app-store` - location types, app-specific metadata schemas
- `@calcom/prisma` - database models and enums
- `@calcom/i18n` - translations for location labels
- `@calcom/lib/intervalLimits` - booking/duration limit parsing and validation

## Gotchas

- When `users` array is empty and there is no team, the system falls back to the current logged-in user as the event owner (backward compatibility)
- Managed event types propagate changes from parent to children, but children can have individual overrides
- The `schedule` field on EventType refers to a `scheduleId`, not an inline schedule definition
- `instantMeetingSchedule` is a separate schedule used specifically for instant meeting availability windows
- `restrictionSchedule` is yet another schedule relation used for booking restriction windows
- Team booking limits (`team.bookingLimits`) are separate from event type booking limits and are checked additionally

## Related Concepts

- [Availability and Scheduling](./availability-and-scheduling.md) - how schedules and slots work
- [Organizations and Teams](./organizations-and-teams.md) - team context for scheduling types
- [Workflows and Automations](./workflows-and-automations.md) - workflows attach to event types
- [Routing Forms](./routing-forms.md) - forms can route to event types
