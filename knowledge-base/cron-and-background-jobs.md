# Cron and Background Jobs

> Cal.com uses two complementary task systems: the **Tasker** (database-backed internal task queue) and the **Trigger.dev Tasker** (async background processing via trigger.dev). Both use a factory/dispatch pattern with typed task payloads.

## Overview

The codebase has two distinct task systems:

1. **Internal Tasker** (`packages/features/tasker/`) - A database-backed task queue using Prisma's `Task` model. Tasks are created in the database and processed via a cron endpoint. This is the default system.

2. **Trigger.dev Tasker** (`packages/lib/tasker/Tasker.ts`) - An abstract base class for dispatching tasks to either trigger.dev (async) or synchronous handlers. Used for specific features like webhook delivery and booking emails. Falls back to sync execution when trigger.dev is not configured.

## Key Locations

| Path | Purpose |
|------|---------|
| `packages/features/tasker/tasker.ts` | Task type definitions and `Tasker` interface |
| `packages/features/tasker/tasker-factory.ts` | `TaskerFactory` and `getTasker()` shorthand |
| `packages/features/tasker/internal-tasker.ts` | `InternalTasker` - default database-backed implementation |
| `packages/features/tasker/redis-tasker.ts` | `RedisTasker` - WIP, not yet implemented |
| `packages/features/tasker/repository.ts` | `TaskRepository` - Prisma data access for Task model |
| `packages/features/tasker/task-processor.ts` | `TaskProcessor` - processes task batches from DB |
| `packages/features/tasker/index.ts` | Singleton tasker export (cached in global) |
| `packages/features/tasker/tasks/index.ts` | Task handler registry with dynamic imports |
| `packages/features/tasker/api/cron.ts` | Cron endpoint to process tasks |
| `packages/features/tasker/api/cleanup.ts` | Cron endpoint to clean up completed tasks |
| `packages/lib/tasker/Tasker.ts` | Abstract `Tasker` base class for trigger.dev integration |
| `packages/features/webhooks/lib/tasker/` | Webhook-specific tasker with trigger.dev support |
| `packages/features/webhooks/lib/tasker/trigger/` | Trigger.dev task definitions for webhooks |

## Patterns

### Internal Tasker - Task Creation
**Where:** `packages/features/tasker/internal-tasker.ts`, `packages/features/tasker/tasker.ts`
**How it works:** Tasks are created with a typed task name and payload. The `Tasker` interface enforces type safety via `TaskPayloads` mapped type. Tasks are stored in the database with optional `scheduledAt`, `maxAttempts`, and `referenceUid`.

**Example:**
```typescript
import tasker from "@calcom/features/tasker";

// Create a task for immediate processing
await tasker.create("sendWebhook", webhookPayloadString);

// Create a scheduled task
await tasker.create("sendAwaitingPaymentEmail", {
  bookingId: 123,
  paymentId: 456,
  attendeeSeatId: null,
}, {
  scheduledAt: new Date(Date.now() + 15 * 60 * 1000), // 15 min delay
  referenceUid: booking.uid,
});

// Cancel a task by reference
await tasker.cancelWithReference(booking.uid, "sendAwaitingPaymentEmail");
```

### Task Type Registry
**Where:** `packages/features/tasker/tasks/index.ts`
**How it works:** All task handlers are registered in a map with lazy dynamic imports to avoid circular dependencies and reduce compilation overhead.

**Example:**
```typescript
const tasks: Record<TaskTypes, () => Promise<TaskHandler>> = {
  sendWebhook: () => import("./sendWebook").then((m) => m.sendWebhook),
  triggerHostNoShowWebhook: () => import("./triggerNoShow/triggerHostNoShow").then((m) => m.triggerHostNoShow),
  createCRMEvent: () => import("./crm/createCRMEvent").then((m) => m.createCRMEvent),
  bookingAudit: () => import("./bookingAudit").then((m) => m.bookingAudit),
  webhookDelivery: () => import("./webhookDelivery").then((m) => m.webhookDelivery),
  // ... more tasks
};

export const tasksConfig = {
  createCRMEvent: { minRetryIntervalMins: IS_PRODUCTION ? 10 : 1, maxAttempts: 10 },
  executeAIPhoneCall: { maxAttempts: 1 },
  webhookDelivery: { minRetryIntervalMins: IS_PRODUCTION ? 5 : 1, maxAttempts: 3 },
};
```

### Cron-Based Task Processing
**Where:** `packages/features/tasker/api/cron.ts`
**How it works:** A Next.js API route endpoint is called by an external cron scheduler (e.g., Vercel Cron). It authenticates via `CRON_SECRET` bearer token, then processes the next batch of tasks.

**Example:**
```typescript
async function handler(request: NextRequest) {
  const authHeader = request.headers.get("authorization");
  if (authHeader !== `Bearer ${process.env.CRON_SECRET}`) {
    return new Response("Unauthorized", { status: 401 });
  }
  const processor = new TaskProcessor();
  await processor.processQueue();
  return NextResponse.json({ success: true });
}
```

### Task Processing Pipeline
**Where:** `packages/features/tasker/task-processor.ts`
**How it works:** `TaskProcessor.processQueue()` fetches up to 1000 pending tasks, processes them concurrently, and marks each as succeeded or retried based on outcome.

**Example:**
```typescript
const tasks = await Task.getNextBatch(); // tasks where scheduledAt < now, not succeeded, attempts < maxAttempts

for (const task of tasks) {
  const taskHandler = await tasksMap[task.type](); // dynamic import
  try {
    await taskHandler(task.payload, task.id);
    await Task.succeed(task.id);
  } catch (error) {
    await Task.retry({
      taskId: task.id,
      lastError: error.message,
      minRetryIntervalMins: taskConfig?.minRetryIntervalMins,
    });
  }
}
```

### Task Repository (Database Layer)
**Where:** `packages/features/tasker/repository.ts`
**How it works:** The `TaskRepository` manages Task records in the database. Tasks have `scheduledAt`, `attempts`, `maxAttempts`, `succeededAt`, `lastError`, and `lastFailedAttemptAt` fields. Retry scheduling pushes `scheduledAt` forward by `minRetryIntervalMins`.

**Key operations:**
- `create(type, payload, options)` - Insert a new task
- `getNextBatch()` - Get up to 1000 tasks ready to process
- `succeed(taskId)` - Mark task as completed
- `retry({ taskId, lastError, minRetryIntervalMins })` - Increment attempts, optionally delay next retry
- `cancelWithReference(referenceUid, type)` - Cancel by composite key

### Trigger.dev Tasker (Abstract Base)
**Where:** `packages/lib/tasker/Tasker.ts`
**How it works:** An abstract `Tasker<T>` class that dispatches to either an async trigger.dev tasker or a sync fallback. Requires `ENABLE_ASYNC_TASKER`, `TRIGGER_SECRET_KEY`, and `TRIGGER_API_URL` env vars. Falls back to sync when trigger.dev is unavailable.

**Example:**
```typescript
export abstract class Tasker<T> {
  constructor(dependencies: { asyncTasker: T; syncTasker: T; logger: ILogger }) {
    if (isAsyncTaskerEnabled) {
      configure({ accessToken: process.env.TRIGGER_SECRET_KEY, baseURL: process.env.TRIGGER_API_URL });
    }
    this.asyncTasker = isAsyncTaskerEnabled ? dependencies.asyncTasker : dependencies.syncTasker;
  }

  public async dispatch<K extends keyof T>(taskName: K, ...args): Promise<ReturnType<T[K]>> {
    // Try async, fall back to sync on failure
  }
}
```

### Trigger.dev Webhook Delivery
**Where:** `packages/features/webhooks/lib/tasker/trigger/deliver-webhook.ts`
**How it works:** A trigger.dev `schemaTask` that processes webhook deliveries in the background. Uses a concurrency-limited queue (25) with exponential backoff retries.

**Example:**
```typescript
export const deliverWebhook = schemaTask({
  id: "webhook.deliver",
  machine: "small-1x",
  queue: webhookDeliveryQueue, // concurrencyLimit: 25
  retry: { maxAttempts: 3, factor: 2, minTimeoutInMs: 30000, maxTimeoutInMs: 600000 },
  schema: webhookDeliveryTaskSchema,
  run: async (payload, { ctx }) => {
    const webhookTaskConsumer = getWebhookTaskConsumer(); // from DI container
    await webhookTaskConsumer.processWebhookTask(payload, ctx.run.id);
  },
});
```

### Singleton Tasker Export
**Where:** `packages/features/tasker/index.ts`
**How it works:** The tasker is cached on the Node.js `global` object in development to survive HMR. In production, a new instance is created once.

**Example:**
```typescript
const globalForTasker = global as unknown as { tasker: Tasker };
export const tasker = globalForTasker.tasker || getTasker();
if (process.env.NODE_ENV !== "production") {
  globalForTasker.tasker = tasker;
}
```

## Available Task Types

| Task | Purpose |
|------|---------|
| `sendWebhook` | Legacy webhook delivery |
| `webhookDelivery` | New webhook delivery (with DI) |
| `triggerHostNoShowWebhook` | Host no-show detection |
| `triggerGuestNoShowWebhook` | Guest no-show detection |
| `createCRMEvent` | Create events in CRM integrations |
| `sendWorkflowEmails` | Workflow-triggered emails |
| `bookingAudit` | Booking audit trail |
| `translateEventTypeData` | AI translation of event types |
| `sendAwaitingPaymentEmail` | Payment reminder emails |
| `sendProrationInvoiceEmail` | Proration billing emails |
| `executeAIPhoneCall` | AI phone call execution |
| `scanWorkflowBody` | Workflow content scanning |

## Conventions

- Import tasker from `@calcom/features/tasker` (the singleton)
- Task handlers receive `(payload: string, taskId?: string)` and return `Promise<void>`
- Task payloads are typed via the `TaskPayloads` map in `tasker.ts`
- Dynamic imports in the task registry prevent circular dependencies
- The `CRON_SECRET` env var protects cron endpoints from unauthorized access
- Use `referenceUid` for tasks that may need to be cancelled later (e.g., payment reminders)

## Dependencies

- `@calcom/prisma` - Task model for database-backed queue
- `@trigger.dev/sdk` - trigger.dev SDK for async task processing
- Environment variables:
  - `CRON_SECRET` - Authentication for cron endpoints
  - `ENABLE_ASYNC_TASKER` - Toggle trigger.dev async processing
  - `TRIGGER_SECRET_KEY` - trigger.dev API key
  - `TRIGGER_API_URL` - trigger.dev API endpoint

## Gotchas

- The `RedisTasker` exists but is **not implemented** (all methods throw). Only `InternalTasker` works
- The task processor fetches up to 1000 tasks per batch -- very large queues may need multiple cron invocations
- Task retry scheduling uses `minRetryIntervalMins` to prevent hammering -- this pushes `scheduledAt` forward
- The `cleanup()` method in `TaskRepository` is currently commented out (TODO)
- Trigger.dev fallback to sync means if async fails, the sync handler runs in the same request context
- `hasNewerScanTaskForStepId` uses raw SQL (`$queryRaw`) to check JSON payload fields

## Related Concepts

- [Dependency Injection](./dependency-injection.md) - Tasker services and webhook consumers use DI
- [Payments and Stripe](./payments-and-stripe.md) - Payment reminder emails use the tasker
- [Docker and Deployment](./docker-and-deployment.md) - Cron jobs need external scheduling (Vercel Cron, etc.)
