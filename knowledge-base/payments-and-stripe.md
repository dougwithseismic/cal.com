# Payments and Stripe

> Cal.com integrates Stripe as a payment app-store entry, using OAuth Connect for merchant onboarding and the `IAbstractPaymentService` interface for a pluggable payment architecture.

## Overview

The payment system is built around the `IAbstractPaymentService` interface, which defines methods for creating charges, collecting cards (for no-show fees), refunding, and cleanup. Stripe is the primary implementation, living in the app store as `stripepayment`. Payments are linked to bookings via the `Payment` Prisma model. The system supports both immediate charges (`ON_BOOKING`) and delayed card holds (`HOLD`).

## Key Locations

| Path | Purpose |
|------|---------|
| `packages/types/PaymentService.d.ts` | `IAbstractPaymentService` interface all payment apps implement |
| `packages/lib/payment/types.ts` | `RefundPolicy` enum (NEVER, ALWAYS, DAYS) |
| `packages/app-store/stripepayment/` | Stripe app-store integration |
| `packages/app-store/stripepayment/lib/PaymentService.ts` | Stripe `IAbstractPaymentService` implementation |
| `packages/app-store/stripepayment/lib/server.ts` | Stripe SDK singleton and data schemas |
| `packages/app-store/stripepayment/api/add.ts` | OAuth Connect authorization redirect |
| `packages/app-store/stripepayment/api/callback.ts` | OAuth callback to store credentials |
| `packages/app-store/stripepayment/api/paymentCallback.ts` | Post-payment processing callback |
| `packages/app-store/stripepayment/lib/customer.ts` | Stripe customer management |
| `packages/app-store/stripepayment/lib/subscriptions.ts` | Subscription retrieval utilities |
| `packages/app-store/stripepayment/lib/services/` | Billing portal services (user, team, org) |
| `packages/app-store/stripepayment/zod.ts` | Zod schemas for payment options and app keys |
| `packages/features/credentials/handleDeleteCredential.ts` | Payment credential deletion with booking cleanup |

## Patterns

### Payment Service Interface
**Where:** `packages/types/PaymentService.d.ts`
**How it works:** All payment apps must implement `IAbstractPaymentService`, which defines the full payment lifecycle.

**Example:**
```typescript
export interface IAbstractPaymentService {
  create(payment, bookingId, userId, username, bookerName, paymentOption, bookerEmail, ...): Promise<Payment>;
  collectCard(payment, bookingId, paymentOption, bookerEmail, ...): Promise<Payment>;
  chargeCard(payment, bookingId?): Promise<Payment>;
  refund(paymentId): Promise<Payment | null>;
  afterPayment(event, booking, paymentData, eventTypeMetadata?): Promise<void>;
  deletePayment(paymentId): Promise<boolean>;
  isSetupAlready(): boolean;
}
```

### Stripe Payment Service
**Where:** `packages/app-store/stripepayment/lib/PaymentService.ts`
**How it works:** The `StripePaymentService` class implements the interface. It uses the platform Stripe key (`STRIPE_PRIVATE_KEY`) for API calls but connects to the merchant's account via `stripeAccount` (Stripe Connect). Credentials store the merchant's `stripe_user_id`, `default_currency`, and `stripe_publishable_key`.

**Example (creating a payment):**
```typescript
// Inside StripePaymentService.create():
const customer = await retrieveOrCreateStripeCustomerByEmail(
  this.credentials.stripe_user_id, bookerEmail, bookerPhoneNumber
);

const paymentIntent = await this.stripe.paymentIntents.create(params, {
  stripeAccount: this.credentials.stripe_user_id,  // Connect account
});

const paymentData = await prisma.payment.create({
  data: {
    uid: uuidv4(),
    app: { connect: { slug: "stripe" } },
    booking: { connect: { id: bookingId } },
    amount: payment.amount,
    currency: payment.currency,
    externalId: paymentIntent.id,
    data: { ...paymentIntent, stripe_publishable_key, stripeAccount } as Prisma.InputJsonValue,
    paymentOption: "ON_BOOKING",
  },
});
```

### Factory Export Pattern
**Where:** `packages/app-store/stripepayment/lib/PaymentService.ts`
**How it works:** The class is not exported directly. Instead, a factory function is exported to prevent Stripe SDK types from leaking into declaration files.

**Example:**
```typescript
export function BuildPaymentService(credentials: { key: Prisma.JsonValue }): IAbstractPaymentService {
  return new StripePaymentService(credentials);
}
```

### Stripe OAuth Connect Setup
**Where:** `packages/app-store/stripepayment/api/add.ts`, `packages/app-store/stripepayment/api/callback.ts`
**How it works:** The add endpoint generates a Stripe Connect OAuth URL. After the merchant authorizes, the callback exchanges the code for tokens and stores them as a credential.

**Flow:**
1. `GET /api/integrations/stripepayment/add` - Returns the Stripe Connect OAuth authorize URL
2. User authorizes on Stripe
3. `GET /api/integrations/stripepayment/callback` - Exchanges code, retrieves account details, stores credential

**Example (callback):**
```typescript
const response = await stripe.oauth.token({ grant_type: "authorization_code", code });
const data: StripeData = { ...response, default_currency: "" };
if (response.stripe_user_id) {
  const account = await stripe.accounts.retrieve(response.stripe_user_id);
  data.default_currency = account.default_currency;
}
await createOAuthAppCredential({ appId: "stripe", type: "stripe_payment" }, data, req);
```

### Awaiting Payment Email (Post-Payment Hook)
**Where:** `packages/app-store/stripepayment/lib/PaymentService.ts`
**How it works:** After creating a payment, `afterPayment` schedules a tasker job to send an "awaiting payment" email if the payment isn't completed within a delay period (default 15 minutes).

**Example:**
```typescript
async afterPayment(event, booking, paymentData) {
  const delayMinutes = Number(process.env.AWAITING_PAYMENT_EMAIL_DELAY_MINUTES) || 15;
  const scheduledEmailAt = dayjs().add(delayMinutes, "minutes").toDate();

  await tasker.create("sendAwaitingPaymentEmail", {
    bookingId: booking.id,
    paymentId: paymentData.id,
    attendeeSeatId: event.attendeeSeatId || null,
  }, {
    scheduledAt: scheduledEmailAt,
    referenceUid: booking.uid,
  });
}
```

### Payment Credential Deletion Cascade
**Where:** `packages/features/credentials/handleDeleteCredential.ts`
**How it works:** When a payment credential is deleted, all pending unpaid bookings for that payment app are cancelled, their payments deleted, attendees removed, and cancellation emails sent.

### Team/Org Billing Portal
**Where:** `packages/app-store/stripepayment/lib/services/`
**How it works:** Billing portal services are split by entity type with a factory pattern:
- `UserBillingPortalService` - Individual user billing
- `TeamBillingPortalService` - Team billing
- `OrganizationBillingPortalService` - Organization billing
- `BillingPortalServiceFactory` - Selects the right service

### Stripe Configuration
**Where:** `packages/app-store/stripepayment/lib/server.ts`
**How it works:** A singleton Stripe SDK instance is created with `STRIPE_PRIVATE_KEY`. The API version is pinned to `2020-08-27`.

**Example:**
```typescript
const stripePrivateKey = process.env.STRIPE_PRIVATE_KEY || "";
const stripe = new Stripe(stripePrivateKey, { apiVersion: "2020-08-27" });
export default stripe;
```

## Conventions

- Payment amounts are stored in the smallest currency unit (cents for USD)
- The `Payment` model's `data` field stores the full Stripe response as JSON
- `externalId` on Payment maps to Stripe's `paymentIntent.id` or `setupIntent.id`
- Payment options: `ON_BOOKING` (immediate charge) or `HOLD` (collect card, charge later)
- Refund policy is per event type: `NEVER`, `ALWAYS`, or `DAYS` (refundable within X days)
- Stripe app keys (`client_id`, `payment_fee_fixed`, etc.) come from the `App.keys` database field, parsed via Zod

## Dependencies

- `stripe` - Stripe Node.js SDK
- `@calcom/features/tasker` - For scheduling delayed payment emails
- `@calcom/prisma` - Payment, Booking, Credential models
- Environment variables:
  - `STRIPE_PRIVATE_KEY` - Platform Stripe secret key
  - `STRIPE_API_KEY` - Used by API v2
  - `STRIPE_WEBHOOK_SECRET` - For webhook signature verification
  - `STRIPE_PRICE_ID_*` - Subscription pricing tier IDs
  - `IS_TEAM_BILLING_ENABLED` - Toggle for team billing
  - `AWAITING_PAYMENT_EMAIL_DELAY_MINUTES` - Delay before sending payment reminder (default: 15)

## Gotchas

- The Stripe API version is pinned to `2020-08-27` -- updating requires careful testing
- The `StripePaymentService` constructor gracefully handles missing credentials (sets `this.credentials = null`) but most methods will throw if credentials are null
- The factory export pattern (`BuildPaymentService`) means you cannot `instanceof` check the class externally
- Payment deletion in Stripe involves expiring checkout sessions before cancelling the payment intent
- When a payment credential is deleted, pending bookings are cancelled with "Payment method removed" reason

## Related Concepts

- [Credentials and OAuth](./credentials-and-oauth.md) - Stripe uses OAuth Connect for merchant credential setup
- [App Store Integrations](./app-store-integrations.md) - Stripe is an app-store entry in the `payment` category
- [Cron and Background Jobs](./cron-and-background-jobs.md) - Payment reminder emails are scheduled via tasker
