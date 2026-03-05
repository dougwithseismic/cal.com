# Email and Notifications

> Cal.com sends emails via Nodemailer with React-rendered templates, SMS via Twilio (with credit-based billing), webhooks via HTTP POST with HMAC signatures, and push notifications via Web Push (VAPID). All notification types integrate with the booking lifecycle through the `EmailManager`.

## Overview

The notification system spans four channels: email, SMS, webhooks, and push notifications. The `EmailManager` in `packages/emails/` orchestrates both email and SMS sending for booking events. Emails are React components rendered to static HTML via `react-dom/server`. SMS uses Twilio with rate limiting and credit checks. Webhooks support custom payload templates (Handlebars), scheduled delivery via a tasker system, and versioned payload builders. Push notifications use the Web Push API with VAPID keys.

## Key Locations

| Path | Purpose |
|------|---------|
| `packages/emails/email-manager.ts` | Central orchestrator for email and SMS dispatch |
| `packages/emails/templates/_base-email.ts` | Base class for all email templates (Nodemailer transport) |
| `packages/emails/templates/attendee-scheduled-email.ts` | Example: confirmation email to attendees |
| `packages/emails/templates/organizer-scheduled-email.ts` | Example: notification to organizer |
| `packages/emails/src/renderEmail.ts` | Renders React email components to static HTML |
| `packages/emails/src/templates/` | React JSX email template components |
| `packages/emails/src/components/` | Shared email UI components |
| `packages/emails/email-types.ts` | Email type enum (CONFIRMATION, CANCELLATION, etc.) |
| `packages/sms/sms-manager.ts` | Abstract SMS manager base class |
| `packages/sms/attendee/event-scheduled-sms.ts` | SMS for booking confirmation |
| `packages/sms/attendee/event-cancelled-sms.ts` | SMS for booking cancellation |
| `packages/features/webhooks/lib/sendPayload.ts` | Core webhook HTTP delivery with HMAC signing |
| `packages/features/webhooks/lib/WebhookService.ts` | High-level webhook service (init + send) |
| `packages/features/webhooks/lib/getWebhooks.ts` | Query webhook subscribers from DB |
| `packages/features/webhooks/lib/sendOrSchedulePayload.ts` | Routes to sync send or tasker-based scheduling |
| `packages/features/webhooks/lib/constants.ts` | Webhook trigger event constants |
| `packages/features/webhooks/lib/service/WebhookNotificationHandler.ts` | Versioned webhook notification handler |
| `packages/features/webhooks/lib/factory/versioned/PayloadBuilderFactory.ts` | Factory for version-specific payload builders |
| `packages/features/webhooks/lib/factory/versioned/v2021-10-20/` | Default version payload builders |
| `packages/features/webhooks/lib/tasker/` | Tasker-based async webhook delivery |
| `packages/features/notifications/sendNotification.ts` | Web Push notification sender |

## Patterns

### Email Template System
**Where:** `packages/emails/templates/_base-email.ts`
**How it works:** All email templates extend `BaseEmail`. Each template overrides `getNodeMailerPayload()` to return a Nodemailer-compatible object with `to`, `from`, `subject`, `html`, and optional `icalEvent`. The `sendEmail()` method creates a Nodemailer transport from `serverConfig`, checks for a kill switch feature flag (`emails`), and sends. Integration test mode captures emails in `globalThis.testEmails`.
**Example:**
```typescript
export default class BaseEmail {
  public async sendEmail() {
    const featuresRepository = new FeaturesRepository(prisma);
    const emailsDisabled = await featuresRepository.checkIfFeatureIsEnabledGlobally("emails");
    if (emailsDisabled) return;

    const payload = await this.getNodeMailerPayload();
    const { createTransport } = await import("nodemailer");
    await createTransport(this.getMailerOptions().transport).sendMail(payloadWithUnEscapedSubject);
  }

  protected getMailerOptions() {
    return {
      transport: serverConfig.transport,
      from: serverConfig.from,
      headers: serverConfig.headers,
    };
  }
}
```

### Email Rendering (React to HTML)
**Where:** `packages/emails/src/renderEmail.ts`
**How it works:** Email templates are React components. The `renderEmail` function dynamically imports `react-dom/server` and calls `renderToStaticMarkup` on the component. The output is cleaned up (script tags removed) and namespaced with XML for Outlook compatibility.
**Example:**
```typescript
async function renderEmail<K extends keyof typeof templates>(
  template: K,
  props: React.ComponentProps<(typeof templates)[K]>
) {
  const ReactDOMServer = (await import("react-dom/server")).default;
  return ReactDOMServer.renderToStaticMarkup(Component(props))
    .replace(/<script><\/script>/g, "")
    .replace("<html>", `<html xmlns="http://www.w3.org/1999/xhtml" ...>`);
}
```

### EmailManager (Booking Lifecycle)
**Where:** `packages/emails/email-manager.ts`
**How it works:** The `EmailManager` contains static methods for each booking event (`sendScheduledEmailsAndSMS`, `sendCancelledEmailsAndSMS`, `sendRescheduledEmailsAndSMS`, etc.). Each method sends both emails and SMS in parallel. Email suppression is controlled at two levels: per-event-type metadata (`disableStandardEmails.all.attendee` / `.host`) and per-organization settings (e.g., `disableAttendeeCancellationEmail`).

**Example of the send pattern:**
```typescript
const _sendScheduledEmailsAndSMS = async (calEvent, eventNameObject, hostEmailDisabled, attendeeEmailDisabled) => {
  const emailsToSend: Promise<unknown>[] = [];
  const organizationSettings = await fetchOrganizationEmailSettings(calEvent.organizationId);

  if (!hostEmailDisabled && !eventTypeDisableHostEmail(eventTypeMetadata)) {
    emailsToSend.push(sendEmail(() => new OrganizerScheduledEmail({ calEvent })));
  }
  if (!attendeeEmailDisabled && !shouldSkipAttendeeEmailWithSettings(metadata, orgSettings, EmailType.CONFIRMATION)) {
    emailsToSend.push(...calEvent.attendees.map(attendee =>
      sendEmail(() => new AttendeeScheduledEmail(calEvent, attendee))
    ));
  }
  // SMS sent in parallel
  const smsSender = new EventSuccessfullyScheduledSMS(calEvent);
  await smsSender.sendSMSToAttendees();
  await Promise.all(emailsToSend);
};
```

### SMS Notification System
**Where:** `packages/sms/sms-manager.ts`
**How it works:** `SMSManager` is an abstract base class. Concrete implementations (e.g., `EventSuccessfullyScheduledSMS`) provide the message text via `getMessage(attendee)`. SMS is sent only to phone-only bookings (detected via `isSmsCalEmail`). It uses `sendSmsOrFallbackEmail` from the workflows package (Twilio), with rate limiting and credit checking.
**Example:**
```typescript
export default abstract class SMSManager {
  abstract getMessage(attendee: Person): string;

  async sendSMSToAttendee(attendee: Person, bookingUid?: string | null) {
    const attendeePhoneNumber = attendee.phoneNumber;
    const isPhoneOnlyBooking = attendeePhoneNumber && isSmsCalEmail(attendee.email);
    if (!attendeePhoneNumber || !isPhoneOnlyBooking || !(await this.isSMSNotificationEnabled())) return;

    const smsMessage = this.getMessage(attendee);
    const senderID = getSenderId(attendeePhoneNumber, SENDER_ID);
    return handleSendingSMS({ reminderPhone: attendeePhoneNumber, smsMessage, senderID, teamId, bookingUid });
  }
}
```

SMS types available:
- `event-scheduled-sms.ts` -- Booking confirmation
- `event-cancelled-sms.ts` -- Booking cancellation
- `event-rescheduled-sms.ts` -- Booking rescheduled
- `event-declined-sms.ts` -- Booking declined
- `event-request-sms.ts` -- Booking request (pending approval)
- `event-request-to-reschedule-sms.ts` -- Reschedule request
- `event-location-changed-sms.ts` -- Location change
- `awaiting-payment-sms.ts` -- Payment pending
- `cancelled-seat-sms.ts` -- Seat cancellation

### Webhook System
**Where:** `packages/features/webhooks/lib/`
**How it works:** Webhooks are stored in the `Webhook` table with subscriber URLs, event triggers, optional payload templates, secrets, and version. When a trigger event occurs:

1. `getWebhooks()` queries all matching subscribers (by userId, eventTypeId, teamId, orgId, oAuthClientId)
2. `sendOrSchedulePayload()` either sends immediately or schedules via tasker (`TASKER_ENABLE_WEBHOOKS=1`)
3. `sendPayload()` formats the payload, applies Handlebars templates if configured, and sends via `fetch()`
4. HMAC-SHA256 signature is added as `X-Cal-Signature-256` header

**Webhook delivery:**
```typescript
const _sendPayload = async (secretKey, webhook, body, contentType) => {
  const response = await fetch(webhook.subscriberUrl, {
    method: "POST",
    headers: {
      "Content-Type": contentType,
      "X-Cal-Signature-256": createWebhookSignature({ secret: secretKey, body }),
      "X-Cal-Webhook-Version": version,
    },
    body,
  });
  return { ok: response.ok, status: response.status };
};
```

**Trigger events:**
```typescript
// Core events
BOOKING_CANCELLED, BOOKING_CREATED, BOOKING_RESCHEDULED, BOOKING_PAID,
BOOKING_PAYMENT_INITIATED, MEETING_ENDED, MEETING_STARTED, BOOKING_REQUESTED,
BOOKING_REJECTED, RECORDING_READY, INSTANT_MEETING,
RECORDING_TRANSCRIPTION_GENERATED, BOOKING_NO_SHOW_UPDATED,
OOO_CREATED, DELEGATION_CREDENTIAL_ERROR, WRONG_ASSIGNMENT_REPORT,
AFTER_HOSTS_CAL_VIDEO_NO_SHOW, AFTER_GUESTS_CAL_VIDEO_NO_SHOW

// Routing form events
FORM_SUBMITTED, FORM_SUBMITTED_NO_EVENT, ROUTING_FORM_FALLBACK_HIT
```

### Versioned Webhook Payloads
**Where:** `packages/features/webhooks/lib/factory/versioned/`
**How it works:** The webhook system supports versioned payload builders via a factory pattern. Currently there is one version (`v2021-10-20`). The `PayloadBuilderFactory` creates version-specific builders for different event types (booking, form, OOO, recording, meeting, instant meeting, delegation). Each builder implements a common interface to construct the webhook payload.

### Webhook Tasker (Async Delivery)
**Where:** `packages/features/webhooks/lib/tasker/`
**How it works:** When `TASKER_ENABLE_WEBHOOKS=1`, webhook payloads are enqueued to a job queue (`WebhookTriggerTasker`) instead of sent synchronously. The `WebhookTaskConsumer` processes jobs and delivers webhooks. The `WebhookSyncTasker` handles synchronous delivery as a fallback. This decouples webhook delivery from the booking flow.

### Push Notifications (VAPID)
**Where:** `packages/features/notifications/sendNotification.ts`
**How it works:** Uses the `web-push` library with VAPID keys (`NEXT_PUBLIC_VAPID_PUBLIC_KEY`, `VAPID_PRIVATE_KEY`). If keys are configured, `sendNotification()` sends push notifications with title, body, icon, URL, and optional action buttons. Currently used primarily for instant meeting notifications.
**Example:**
```typescript
webpush.setVapidDetails("mailto:support@cal.com", vapidKeys.publicKey, vapidKeys.privateKey);

export const sendNotification = async ({ subscription, title, body, icon, url, actions, type = "INSTANT_MEETING" }) => {
  if (!isVapidConfigured) return;
  const payload = JSON.stringify({
    title, body, icon,
    data: { url, type },
    actions,
    tag: `cal-notification-${Date.now()}`,
  });
  await webpush.sendNotification(subscription, payload);
};
```

## Conventions

- Email templates follow a naming convention: `attendee-{action}-email.ts` and `organizer-{action}-email.ts`
- SMS classes follow: `event-{action}-sms.ts` under `packages/sms/attendee/`
- Webhook payload templates use Handlebars syntax
- Webhook signature header: `X-Cal-Signature-256` (HMAC-SHA256 of body with webhook secret)
- Webhook version header: `X-Cal-Webhook-Version`
- Zapier webhooks get a special payload format (hardcoded check for `appId === "zapier"`)
- Email kill switch via feature flag `emails` in the database
- `isSmsCalEmail` detects phone-only bookings (faux email addresses)

## Dependencies

- `nodemailer` -- Email transport
- `react-dom/server` -- Server-side rendering of email templates
- `web-push` -- Push notification delivery
- `handlebars` -- Webhook payload templating
- `@calcom/features/ee/workflows/lib/reminders/messageDispatcher` -- Twilio SMS integration
- `@calcom/features/ee/billing/credit-service` -- SMS credit checking
- `entities` -- HTML entity decoding for email subjects

## Gotchas

- The `emailsDisabled` kill switch is checked via a feature flag in the database, not an env var. Setting the `emails` feature flag to enabled will DISABLE emails (counterintuitive naming -- it's a kill switch).
- SMS is only sent to "phone-only" bookings where the attendee's email matches the `isSmsCalEmail` pattern. Regular attendees with phone numbers do NOT get SMS.
- Organization settings can independently disable specific email types (confirmation, cancellation, etc.) per organization.
- Webhook delivery is synchronous by default. Set `TASKER_ENABLE_WEBHOOKS=1` to enable async delivery via job queue.
- The `serverConfig.transport` for Nodemailer is configured via environment variables (SMTP settings).
- SMS rate limiting uses different identifiers: team ID, organizer user ID, or hashed phone number.

## Related Concepts

- [Booking Flow](./booking-flow.md) -- triggers email/SMS/webhook notifications
- [API v2 NestJS](./api-v2-nestjs.md) -- webhook management endpoints
