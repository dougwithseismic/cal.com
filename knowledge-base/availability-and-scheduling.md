# Availability and Scheduling

> How cal.com computes user availability, builds date ranges, calculates slots, and handles busy times, buffers, and period types.

## Overview

The availability system determines when a user is bookable. It starts from a `Schedule` (weekly working hours + date overrides), converts those into `DateRange[]` arrays in the user's timezone, subtracts busy times (from calendars, booking limits, out-of-office), and then slices the remaining free ranges into bookable time slots. The core pipeline is: Schedule -> DateRanges -> subtract BusyTimes -> getSlots.

## Key Locations

| Path | Purpose |
|------|---------|
| `packages/prisma/schema.prisma` (line ~969) | `Schedule` and `Availability` Prisma models |
| `packages/lib/availability.ts` | Default schedule, `getWorkingHours()`, `getAvailabilityFromSchedule()` |
| `packages/features/schedules/lib/date-ranges.ts` | `buildDateRanges()`, `intersect()`, `subtract()`, date range math |
| `packages/features/schedules/lib/slots.ts` | `getSlots()` / `buildSlotsWithDateRanges()` - slot computation |
| `packages/features/availability/lib/getUserAvailability.ts` | `UserAvailabilityService` - main orchestrator |
| `packages/features/availability/lib/getAggregatedAvailability/getAggregatedAvailability.ts` | Merges availability across multiple team members |
| `packages/features/availability/lib/detectEventTypeScheduleForUser.ts` | Resolves which schedule applies to a user for a given event type |
| `packages/features/schedules/repositories/ScheduleRepository.ts` | Database queries for schedules |
| `packages/features/schedules/services/ScheduleService.ts` | Schedule CRUD (create/update) |
| `packages/features/busyTimes/lib/getBusyTimesFromLimits.ts` | Converts booking/duration limits into busy time blocks |

## Patterns

### Schedule Data Model
**Where:** `packages/prisma/schema.prisma:969-1000`
**How it works:** A `Schedule` belongs to a `User` and contains multiple `Availability` rows. Each `Availability` has `days` (array of day-of-week integers 0-6), `startTime`/`endTime` (stored as UTC `@db.Time`), and an optional `date` field for date overrides. When `date` is set and `days` is empty, it is a date override rather than a recurring weekly rule.

```prisma
model Schedule {
  id           Int            @id @default(autoincrement())
  user         User           @relation(fields: [userId], references: [id], onDelete: Cascade)
  userId       Int
  name         String
  timeZone     String?
  availability Availability[]
}

model Availability {
  id          Int        @id @default(autoincrement())
  days        Int[]
  startTime   DateTime   @db.Time
  endTime     DateTime   @db.Time
  date        DateTime?  @db.Date
  scheduleId  Int?
}
```

### Default Schedule
**Where:** `packages/lib/availability.ts:9-22`
**How it works:** When no schedule exists, a default Mon-Fri 9:00-17:00 UTC schedule is used. The `DEFAULT_SCHEDULE` is a 7-element array (one per weekday starting Sunday=0), with empty arrays for Sunday and Saturday.

```typescript
export const DEFAULT_SCHEDULE: Schedule = [
  [],                    // Sunday
  [defaultDayRange],     // Monday
  [defaultDayRange],     // Tuesday
  [defaultDayRange],     // Wednesday
  [defaultDayRange],     // Thursday
  [defaultDayRange],     // Friday
  [],                    // Saturday
];
```

### Schedule Resolution Priority
**Where:** `packages/features/availability/lib/detectEventTypeScheduleForUser.ts:60-101`
**How it works:** When determining which schedule to use, the system follows a priority chain:

1. Event type's explicit schedule (`eventType.schedule`)
2. Host-level schedule (`eventType.hosts[].schedule`)
3. User's default schedule (`user.schedules` filtered by `defaultScheduleId`)
4. Fallback: a hardcoded 9-5 Mon-Fri schedule

```typescript
if (eventType?.schedule) {
  potentialSchedule = eventType.schedule;
} else if (hostSchedule) {
  potentialSchedule = hostSchedule;
} else if (userSchedule) {
  potentialSchedule = userSchedule;
}
const schedule = potentialSchedule ?? fallbackSchedule;
```

### Building Date Ranges from Availability
**Where:** `packages/features/schedules/lib/date-ranges.ts:226-330`
**How it works:** `buildDateRanges()` takes availability entries, a timezone, a date range, and travel schedules. It processes working hours (recurring weekly) and date overrides separately. Date overrides for a given day *replace* working hours for that day (via object key collision in the spread `{...groupedWorkingHours, ...groupedDateOverrides}`). The result includes both standard `dateRanges` and `oooExcludedDateRanges` (which additionally exclude out-of-office days).

### Timezone Handling with Travel Schedules
**Where:** `packages/features/schedules/lib/date-ranges.ts:16-29`
**How it works:** Travel schedules allow a user's timezone to shift for specific date ranges. `getAdjustedTimezone()` checks if a given date falls within any travel schedule range and returns the appropriate timezone. This is only applied when the user is on their default schedule.

### Working Hours Conversion
**Where:** `packages/lib/availability.ts:61-127`
**How it works:** `getWorkingHours()` converts UTC-stored availability into minutes-from-midnight in the target timezone. It handles timezone offset overflow by splitting ranges that cross midnight into two separate entries on adjacent days. Times are clamped to 0-1439 minutes (0:00 to 23:59).

### Slot Computation
**Where:** `packages/features/schedules/lib/slots.ts:71-230`
**How it works:** `buildSlotsWithDateRanges()` iterates through ordered date ranges and generates slots at `frequency`-minute intervals. Key behaviors:

- Enforces `minimumBookingNotice` - no slots before `now + minimumBookingNotice`
- Respects `offsetStart` to shift slot start times
- Uses an interval alignment system (60, 30, 20, 15, 10, 5 min) to snap slots to clean boundaries
- Handles out-of-office by marking slots as `away: true` with redirect info
- When `showOptimizedSlots` is true, tries to maximize available slots by using the raw start time rather than rounding up

```typescript
while (!slotStartTime.add(eventLength, "minutes").subtract(1, "second").utc().isAfter(range.end)) {
  slots.set(slotKey, slotData);
  slotStartTime = slotStartTime.add(frequency + (offsetStart ?? 0), "minutes");
}
```

### User Availability Orchestration
**Where:** `packages/features/availability/lib/getUserAvailability.ts:342-658`
**How it works:** `UserAvailabilityService._getUserAvailability()` is the main entry point. It:

1. Resolves the correct schedule via `detectEventTypeScheduleForUser()`
2. Optionally fetches timezone from delegated calendar credentials (cached in Redis for 6 hours)
3. Computes working hours and date overrides
4. Fetches out-of-office entries and holiday blocked dates
5. Builds date ranges via `buildDateRanges()`
6. Fetches busy times from calendars, booking limits, duration limits, and team booking limits
7. Subtracts busy times from available date ranges: `subtract(dateRanges, formattedBusyTimes)`

### Aggregated Availability for Teams
**Where:** `packages/features/availability/lib/getAggregatedAvailability/getAggregatedAvailability.ts:25-77`
**How it works:** For team events, availability is computed per-member then aggregated:

- **Collective scheduling:** `intersect()` all members' ranges (everyone must be free)
- **Round-robin:** fixed hosts are intersected, round-robin hosts are unioned per group, then all groups are intersected. At least one host from each group must be available
- Groups are determined by `host.groupId`, defaulting to `DEFAULT_GROUP_ID`

### Intersect and Subtract Operations
**Where:** `packages/features/schedules/lib/date-ranges.ts:354-447`
**How it works:** `intersect()` uses a sweep-line algorithm with sorted ranges and pointer advancement to find overlapping windows. `subtract()` removes excluded ranges from source ranges, splitting source ranges when an exclusion falls in the middle.

## Conventions

- All times in the `Availability` model are stored as UTC `@db.Time` values
- Day-of-week uses JavaScript convention: 0=Sunday through 6=Saturday
- `DateRange` objects use dayjs `Dayjs` types for `start` and `end`
- Schedule timezone is optional; falls back to user timezone if not set
- `minimumBookingNotice` defaults to 120 minutes
- The `mode` parameter on availability queries can be `"slots"`, `"overlay"`, `"booking"`, or `"none"`

## Dependencies

- `@calcom/dayjs` - timezone-aware date library (dayjs with plugins)
- `@calcom/prisma` - database models
- `@sentry/nextjs` - performance spans via `withReporting()`
- Redis (via `IRedisService`) - caches delegated calendar timezones

## Gotchas

- Date overrides in the database have known mismatches between local and UTC dates. The code compensates with `.subtract(1, "day")` / `.add(1, "day")` padding when checking if overrides fall in range (see comment at `date-ranges.ts:277-281`)
- The `11:59 PM` edge case: when `endTime` is 23:59, 1 minute is added to effectively make it midnight, since users can only set availability up to 11:59 PM in the UI
- `getWorkingHours()` handles timezone offset overflow to adjacent days, which can create duplicate entries if not careful
- `getUserAvailability` is called per-user in team events but `returnDateOverrides` is not used by `getSchedule`, wasting CPU. There is a TODO to fix this

## Related Concepts

- [Event Types](./event-types.md) - event types reference schedules and define buffer times, period types
- [Organizations and Teams](./organizations-and-teams.md) - team scheduling types affect how availability is aggregated
