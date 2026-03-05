# Workflows and Automations

> Automated email, SMS, WhatsApp, and AI phone call actions triggered by booking lifecycle events and form submissions.

## Overview

The workflow system allows users to create automated sequences triggered by booking events (new, cancelled, rescheduled, etc.) or routing form submissions. Each workflow has a trigger, optional timing (before/after event), and one or more steps that define actions like sending emails, SMS, or initiating AI phone calls. Workflows can be personal, team-level, or organization-wide. Execution is handled via the Tasker system (an async task queue).

## Key Locations

| Path | Purpose |
|------|---------|
| `packages/prisma/schema.prisma` (line ~1556) | `Workflow`, `WorkflowStep`, `WorkflowReminder` models |
| `packages/prisma/schema.prisma` (line ~1494) | `WorkflowTriggerEvents` enum |
| `packages/prisma/schema.prisma` (line ~1511) | `WorkflowActions` enum |
| `packages/prisma/schema.prisma` (line ~1598) | `WorkflowsOnEventTypes` join table |
| `packages/prisma/schema.prisma` (line ~1610) | `WorkflowsOnRoutingForms` join table |
| `packages/prisma/schema.prisma` (line ~1622) | `WorkflowsOnTeams` join table |
| `packages/features/workflows/repositories/WorkflowPermissionsRepository.ts` | Permission checks for workflows |
| `packages/features/tasker/tasker.ts` | Tasker interface and task type definitions |
| `packages/features/tasker/tasker-factory.ts` | Tasker factory (InternalTasker default) |
| `packages/features/tasker/tasks/` | Individual task handlers |
| `packages/trpc/server/routers/viewer/admin/verifyWorkflows.handler.ts` | Admin workflow verification |

## Patterns

### Workflow Data Model
**Where:** `packages/prisma/schema.prisma:1556-1576`
**How it works:** A workflow defines the trigger event, optional timing, and links to steps:

```prisma
model Workflow {
  id            Int                       @id @default(autoincrement())
  name          String
  userId        Int?                      // personal workflow owner
  teamId        Int?                      // team workflow owner
  isActiveOnAll Boolean                   @default(false)
  trigger       WorkflowTriggerEvents
  time          Int?                      // delay amount
  timeUnit      TimeUnit?                 // DAY, HOUR, MINUTE
  steps         WorkflowStep[]
  type          WorkflowType              @default(EVENT_TYPE)
  activeOn      WorkflowsOnEventTypes[]
  activeOnTeams WorkflowsOnTeams[]
  activeOnRoutingForms WorkflowsOnRoutingForms[]
}
```

- `userId` / `teamId`: Ownership - personal or team-scoped
- `isActiveOnAll`: When true, applies to all event types of the owner
- `time` + `timeUnit`: Used with BEFORE_EVENT/AFTER_EVENT triggers for scheduling
- `type`: Either `EVENT_TYPE` or `ROUTING_FORM`

### Trigger Events
**Where:** `packages/prisma/schema.prisma:1494-1509`
**How it works:** The full set of events that can trigger a workflow:

```prisma
enum WorkflowTriggerEvents {
  BEFORE_EVENT                      // Scheduled reminder before event start
  EVENT_CANCELLED                   // Booking was cancelled
  NEW_EVENT                         // New booking created
  AFTER_EVENT                       // Scheduled action after event end
  RESCHEDULE_EVENT                  // Booking was rescheduled
  AFTER_HOSTS_CAL_VIDEO_NO_SHOW     // Host didn't join Cal Video
  AFTER_GUESTS_CAL_VIDEO_NO_SHOW    // Guest didn't join Cal Video
  FORM_SUBMITTED                    // Routing form submitted (with event)
  FORM_SUBMITTED_NO_EVENT           // Routing form submitted (no event routed)
  BOOKING_REJECTED                  // Booking request was rejected
  BOOKING_REQUESTED                 // Booking request was made (requires confirmation)
  BOOKING_PAYMENT_INITIATED         // Payment was initiated
  BOOKING_PAID                      // Payment was completed
  BOOKING_NO_SHOW_UPDATED           // No-show status changed
}
```

### Workflow Actions
**Where:** `packages/prisma/schema.prisma:1511-1520`
**How it works:** Actions define what a step does:

```prisma
enum WorkflowActions {
  EMAIL_HOST                // Send email to the host/organizer
  EMAIL_ATTENDEE            // Send email to the attendee
  SMS_ATTENDEE              // Send SMS to the attendee
  SMS_NUMBER                // Send SMS to a specific number
  EMAIL_ADDRESS             // Send email to a specific address
  WHATSAPP_ATTENDEE         // Send WhatsApp to the attendee
  WHATSAPP_NUMBER           // Send WhatsApp to a specific number
  CAL_AI_PHONE_CALL         // Initiate an AI phone call
}
```

### Workflow Steps
**Where:** `packages/prisma/schema.prisma:1527-1552`
**How it works:** Steps define individual actions within a workflow:

```prisma
model WorkflowStep {
  id                        Int                @id @default(autoincrement())
  stepNumber                Int
  action                    WorkflowActions
  workflowId                Int
  sendTo                    String?            // target phone/email for SMS_NUMBER/EMAIL_ADDRESS
  reminderBody              String?            // message body template
  emailSubject              String?            // email subject template
  template                  WorkflowTemplates  @default(REMINDER)
  numberRequired            Boolean?
  sender                    String?            // sender name/number
  numberVerificationPending Boolean            @default(true)
  includeCalendarEvent      Boolean            @default(false)
  agentId                   String?            // AI agent reference
  autoTranslateEnabled      Boolean            @default(false)
  sourceLocale              String?
  translations              WorkflowStepTranslation[]
}
```

### Workflow Templates
**Where:** `packages/prisma/schema.prisma:1692-1698`
**How it works:** Predefined templates for common workflow step content:

```prisma
enum WorkflowTemplates {
  REMINDER      // Pre-event reminder
  CUSTOM        // Custom user-defined content
  CANCELLED     // Cancellation notification
  RESCHEDULED   // Reschedule notification
  COMPLETED     // Post-event follow-up
  RATING        // Post-event rating request
}
```

### Workflow-to-Event-Type Binding
**Where:** `packages/prisma/schema.prisma:1598-1632`
**How it works:** Workflows connect to their targets through join tables:

- `WorkflowsOnEventTypes`: Links a workflow to specific event types
- `WorkflowsOnRoutingForms`: Links a workflow to specific routing forms
- `WorkflowsOnTeams`: Makes a workflow active across an entire team/org

Each join table uses a composite unique constraint (e.g., `@@unique([workflowId, eventTypeId])`) to prevent duplicates.

### Workflow Type
**Where:** `packages/prisma/schema.prisma:1522-1525`
**How it works:** Distinguishes between event-type workflows and routing-form workflows:

```prisma
enum WorkflowType {
  EVENT_TYPE
  ROUTING_FORM
}
```

### Auto-Translation for Workflow Steps
**Where:** `packages/prisma/schema.prisma:1549-1551, 2471-2483`
**How it works:** Workflow steps can be auto-translated. When `autoTranslateEnabled` is true, translations are stored in `WorkflowStepTranslation`:

```prisma
model WorkflowStepTranslation {
  workflowStepId Int
  field          WorkflowStepAutoTranslatedField
  sourceLocale   String
  targetLocale   String
  translatedText String  @db.Text
  @@unique([workflowStepId, field, targetLocale])
}
```

### Tasker System Architecture
**Where:** `packages/features/tasker/tasker.ts`, `packages/features/tasker/tasker-factory.ts`
**How it works:** The Tasker is an async task queue for executing workflow actions and other deferred work. The interface is:

```typescript
export interface Tasker {
  create: TaskerCreate;    // Enqueue a new task
  cleanup(): Promise<void>;
  cancel(id: string): Promise<string>;
  cancelWithReference(referenceUid: string, type: TaskTypes): Promise<string | null>;
}
```

Tasks can be scheduled for future execution via `scheduledAt` and retried with `maxAttempts`:

```typescript
type TaskerCreate = <TaskKey extends keyof TaskPayloads>(
  type: TaskKey,
  payload: TaskPayloads[TaskKey],
  options?: { scheduledAt?: Date; maxAttempts?: number; referenceUid?: string }
) => Promise<string>;
```

### Tasker Factory
**Where:** `packages/features/tasker/tasker-factory.ts:10-27`
**How it works:** Currently only `InternalTasker` is implemented. The factory is designed to support future alternatives:

```typescript
export class TaskerFactory {
  createTasker(type?: TaskerTypes): Tasker {
    // TODO: Add RedisTasker, TriggerDevTasker, TemporalIOTasker, AWSSQSTasker
    if (type === "internal") return new InternalTasker();
    return new InternalTasker();
  }
}

export function getTasker() {
  return new TaskerFactory().createTasker();
}
```

### Task Types for Workflows
**Where:** `packages/features/tasker/tasker.ts:6-60`
**How it works:** Workflow-related task types in the Tasker system:

- `sendWorkflowEmails` - Sends workflow email notifications
- `scanWorkflowBody` - Scans workflow content for safety
- `scanWorkflowUrls` - Validates URLs in workflow content
- `translateWorkflowStepData` - Auto-translates workflow step content
- `executeAIPhoneCall` - Initiates AI phone calls via agents
- `triggerFormSubmittedNoEventWebhook` - Webhook for form submissions without bookings
- `triggerFormSubmittedNoEventWorkflow` - Workflow trigger for form submissions without bookings
- `sendSms` - Generic SMS sending
- `sendWebhook` - Generic webhook delivery

### Workflow Reminders
**Where:** `packages/prisma/schema.prisma:1652-1668` (after `TimeUnit` enum)
**How it works:** `WorkflowReminder` tracks scheduled reminders. For BEFORE_EVENT triggers with `time` and `timeUnit`, the system creates reminder records that are processed by a cron job at `packages/features/tasker/api/cron.ts`.

### Time Unit for Scheduling
**Where:** `packages/prisma/schema.prisma:1646-1650`

```prisma
enum TimeUnit {
  DAY    @map("day")
  HOUR   @map("hour")
  MINUTE @map("minute")
}
```

Combined with the `time` field on `Workflow`, this controls when BEFORE_EVENT / AFTER_EVENT actions fire (e.g., `time: 24, timeUnit: HOUR` = 24 hours before).

## Conventions

- Workflows belong to either a user (`userId`) or a team (`teamId`), never both
- `isActiveOnAll: true` means the workflow applies to all of the owner's event types
- Phone numbers for SMS require verification (`numberVerificationPending` flag)
- Workflow steps are ordered by `stepNumber`
- The `sender` field on WorkflowStep controls the from name/number
- `includeCalendarEvent: true` attaches calendar event details to the notification
- AI phone calls reference an `Agent` model via `agentId`

## Dependencies

- `packages/features/tasker/` - async task execution
- `packages/features/booking-audit/` - booking audit trail integration
- `packages/features/webhooks/` - webhook delivery through tasker
- `@calcom/prisma` - workflow data models

## Gotchas

- The `InternalTasker` is the only implemented tasker; Redis and other backends are planned but not yet available
- Workflow steps with `numberVerificationPending: true` won't send SMS until the number is verified
- `FORM_SUBMITTED` vs `FORM_SUBMITTED_NO_EVENT`: the former fires when a form submission routes to a booking, the latter when no event type is matched
- Org-wide workflows use `WorkflowsOnTeams` to activate across all teams
- The `verifiedAt` field on `WorkflowStep` tracks when admin verification occurred (for compliance)
- Workflow step translations are only generated when `autoTranslateEnabled` is true and a `sourceLocale` is set

## Related Concepts

- [Event Types](./event-types.md) - workflows bind to event types
- [Routing Forms](./routing-forms.md) - form submission triggers
- [Organizations and Teams](./organizations-and-teams.md) - team/org workflow ownership
