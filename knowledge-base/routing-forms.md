# Routing Forms

> Form builder and routing engine that collects responses and routes users to event types, external URLs, or custom pages based on conditional logic.

## Overview

Routing forms are pre-booking questionnaires that direct users to appropriate event types based on their answers. The system consists of a form builder (fields with types like text, email, phone, select), a route builder using React Awesome Query Builder (RAQB) for conditional logic, and a response handler that evaluates routes and optionally matches team members via attribute-based logic. Forms can be standalone or team-owned, and integrate with CRM routing and workflow triggers.

## Key Locations

| Path | Purpose |
|------|---------|
| `packages/prisma/schema.prisma` (line ~1324) | `App_RoutingForms_Form` model |
| `packages/prisma/schema.prisma` (line ~1354) | `App_RoutingForms_FormResponse` model |
| `packages/features/routing-forms/lib/getRoutedUrl.ts` | Main routing orchestrator (server-side) |
| `packages/features/routing-forms/lib/handleResponse.ts` | Response validation, persistence, attribute matching |
| `packages/features/routing-forms/lib/findTeamMembersMatchingAttributeLogic.ts` | Attribute-based team member matching |
| `packages/features/routing-forms/lib/getUrlSearchParamsToForward.ts` | URL parameter forwarding to booking page |
| `packages/features/routing-forms/lib/isAuthorizedToViewForm.ts` | Org domain authorization |
| `packages/features/routing-forms/lib/types.ts` | `FormResponse`, `Field`, `Fields` types |
| `packages/features/routing-forms/lib/zod.ts` | Zod schemas for fields and responses |
| `packages/features/routing-forms/repositories/PrismaRoutingFormRepository.ts` | Form database queries |
| `packages/features/routing-forms/repositories/RoutingFormResponseRepository.ts` | Response database queries |
| `packages/app-store/routing-forms/lib/processRoute.tsx` | `findMatchingRoute()` - route evaluation engine |
| `packages/app-store/routing-forms/lib/getQueryBuilderConfig.ts` | RAQB config from form fields |
| `packages/app-store/routing-forms/lib/getSerializableForm.ts` | Form serialization for client |
| `packages/app-store/routing-forms/lib/getResponseToStore.ts` | Response normalization |
| `packages/app-store/routing-forms/components/react-awesome-query-builder/` | RAQB config and widgets |
| `packages/app-store/routing-forms/zod.ts` | Route action types schema |
| `packages/trpc/server/routers/apps/routing-forms/` | tRPC handlers |

## Patterns

### Form Data Model
**Where:** `packages/prisma/schema.prisma:1324-1352`
**How it works:** Forms store their fields and routes as JSON:

```prisma
model App_RoutingForms_Form {
  id          String    @id @default(cuid())
  name        String
  description String?
  fields      Json?     // array of field definitions
  routes      Json?     // array of route rules
  userId      Int       // creator/owner
  teamId      Int?      // optional team ownership
  disabled    Boolean   @default(false)
  settings    Json?     // form-level settings
  responses   App_RoutingForms_FormResponse[]
  workflows   WorkflowsOnRoutingForms[]
}
```

- `fields`: JSON array defining form inputs (type, label, required, options)
- `routes`: JSON array defining conditional rules and their actions
- `settings`: Parsed with `RoutingFormSettings` zod schema

### Form Response Model
**Where:** `packages/prisma/schema.prisma:1354-1379`
**How it works:** Responses store the raw submission and routing outcome:

```prisma
model App_RoutingForms_FormResponse {
  id                    Int      @id @default(autoincrement())
  uuid                  String?  @default(uuid())
  formFillerId          String   @default(cuid())
  formId                String
  response              Json     // the actual field responses
  routedToBookingUid    String?  @unique
  chosenRouteId         String?
  @@unique([formFillerId, formId])
}
```

- `formFillerId`: Identifies the form filler for deduplication
- `routedToBookingUid`: Links to the booking created from this response
- `chosenRouteId`: Which route was matched

### Response Types
**Where:** `packages/features/routing-forms/lib/types.ts:5-13`
**How it works:** Form responses use a keyed structure where each field ID maps to its value:

```typescript
export type FormResponse = Record<
  string,  // Field ID
  {
    value: number | string | string[];
    label: string;
    identifier?: string;
  }
>;
```

### Route Matching Engine
**Where:** `packages/app-store/routing-forms/lib/processRoute.tsx:14-69`
**How it works:** `findMatchingRoute()` evaluates routes in order using RAQB logic:

```typescript
export function findMatchingRoute({ form, response, routingFormTraceService }) {
  const queryBuilderConfig = getQueryBuilderConfigForFormFields(form);
  const routes = form.routes || [];
  const fallbackRoute = routes.find(isFallbackRoute);

  const routesWithFallbackInEnd = routes
    .flatMap((r) => isRouter(r) ? r.routes : r)
    .filter((route) => route && !isFallbackRoute(route))
    .concat([fallbackRoute]);

  for (const route of routesWithFallbackInEnd) {
    const result = evaluateRaqbLogic({
      queryValue: route.queryValue as JsonTree,
      queryBuilderConfig,
      data: responseValues,
    });
    if (result === RaqbLogicResult.MATCH || result === RaqbLogicResult.LOGIC_NOT_FOUND_SO_MATCHED) {
      chosenRoute = route;
      break;
    }
  }
  return chosenRoute;
}
```

Key behaviors:
- Routes are evaluated sequentially; first match wins
- Router routes (nested forms) are flattened into the evaluation sequence
- Fallback route is always last and catches unmatched responses
- `LOGIC_NOT_FOUND_SO_MATCHED` means a route with no conditions always matches

### Route Action Types
**Where:** `packages/app-store/routing-forms/zod.ts` (referenced via `RouteActionType`)
**How it works:** Three types of route actions:

1. **`eventTypeRedirectUrl`**: Redirects to a cal.com event type booking page
2. **`externalRedirectUrl`**: Redirects to any external URL
3. **`customPageMessage`**: Shows a custom message page (no redirect)

### Main Routing Flow
**Where:** `packages/features/routing-forms/lib/getRoutedUrl.ts:55-284`
**How it works:** `getRoutedUrl()` orchestrates the full routing pipeline:

1. Parse query params (form ID + field responses)
2. Rate-limit by form ID + response hash
3. Fetch form from database
4. Check org domain authorization
5. Serialize form and build response object
6. Find matching route via `findMatchingRoute()`
7. Call `handleResponse()` for persistence, attribute matching, CRM lookup
8. Save routing trace for debugging
9. Generate redirect URL or custom page response

```typescript
const matchingRoute = findMatchingRoute({ form: serializableForm, response });
const decidedAction = matchingRoute.action;

const result = await handleResponse({
  form: serializableForm,
  response,
  chosenRouteId: matchingRoute.id,
  // ...
});

if (actionToUse.type === "eventTypeRedirectUrl") {
  return { redirect: { destination: getAbsoluteEventTypeRedirectUrlWithEmbedSupport(/* ... */) }};
} else if (actionToUse.type === "externalRedirectUrl") {
  return { redirect: { destination: `${actionToUse.value}?${stringify(context.query)}` }};
} else if (actionToUse.type === "customPageMessage") {
  return { props: { message: actionToUse.value }};
}
```

### Response Handling
**Where:** `packages/features/routing-forms/lib/handleResponse.ts:23-100`
**How it works:** `handleResponse()` validates responses, persists them, and optionally:

- Finds team members matching attribute logic (for round-robin assignment)
- Looks up CRM contact owners for routing
- Supports form response queuing (`queueFormResponse` flag)
- Handles preview/dry-run mode (no persistence)

Validation includes:
- Required field checks
- Email field schema validation
- Invalid field reporting

### Attribute-Based Team Member Matching
**Where:** `packages/features/routing-forms/lib/findTeamMembersMatchingAttributeLogic.ts`
**How it works:** When a route targets a team event type, team members can be filtered based on org-level attributes using RAQB logic:

```typescript
function findTeamMembersMatchingAttributeLogic(data: RunAttributeLogicData) {
  // Uses react-awesome-query-builder to evaluate attribute queries
  // against team member attribute assignments
  // Returns matching team member IDs
}
```

The process:
1. Get org attributes and team member attribute assignments
2. Build RAQB config from attributes
3. Evaluate each team member against the attribute query
4. Return matching members with troubleshooter cases for debugging

### RAQB Integration
**Where:** `packages/app-store/routing-forms/components/react-awesome-query-builder/`
**How it works:** React Awesome Query Builder (RAQB) powers both route conditions and attribute matching:

- `config/BasicConfig.ts` - base RAQB configuration
- `config/config.ts` - cal.com-specific field type mappings
- `widgets.tsx` - custom RAQB widget components
- `config/uiConfig.tsx` - UI customizations

Form fields are converted to RAQB fields via `getQueryBuilderConfigForFormFields()`. The query value (route condition) is stored as a JSON tree structure in `route.queryValue`.

### URL Parameter Forwarding
**Where:** `packages/features/routing-forms/lib/getUrlSearchParamsToForward.ts`
**How it works:** When routing to an event type, form responses and routing metadata are forwarded as URL params:

- Form field values are passed to pre-fill booking fields
- `teamMembersMatchingAttributeLogic` restricts which hosts are shown
- `formResponseId` links the booking back to the form response
- `crmContactOwnerEmail` enables CRM-based host selection
- `attributeRoutingConfig` passes attribute routing configuration

### Deterministic Response Hashing
**Where:** `packages/features/routing-forms/lib/getRoutedUrl.ts:38-48`
**How it works:** Rate limiting uses a SHA-256 hash of the sorted response fields to prevent duplicate submissions:

```typescript
const getDeterministicHashForResponse = (fieldsResponses: Record<string, unknown>) => {
  const sortedFields = Object.keys(fieldsResponses).sort().reduce(/* ... */);
  return createHash("sha256").update(JSON.stringify(sortedFields)).digest("hex");
};
```

### Org Domain Authorization
**Where:** `packages/features/routing-forms/lib/isAuthorizedToViewForm.ts`
**How it works:** Forms served on org domains must belong to the org. `isAuthorizedToViewFormOnOrgDomain()` validates that the form's user profile or team matches the current org domain.

### Queued Form Responses
**Where:** `packages/prisma/schema.prisma:1381-1383`
**How it works:** `App_RoutingForms_QueuedFormResponse` supports async processing of form submissions. When `cal.queueFormResponse=true` is passed as a query param, the response is queued rather than processed immediately.

### Routing Trace
**Where:** `packages/features/routing-trace/` (referenced in `getRoutedUrl.ts`)
**How it works:** The routing trace system records the decision path through the routing engine for debugging. Each routing decision (route matched, attribute filter applied, fallback used) is tracked and persisted via `RoutingTraceService` and `RoutingFormTraceService`.

### Variable Substitution
**Where:** referenced via `substituteVariables()` in `getRoutedUrl.ts:231`
**How it works:** Event type redirect URLs can contain variables that are replaced with form response values. For example, `{{field:name}}` in the URL gets substituted with the actual response value.

## Conventions

- Form IDs are CUIDs (string), not auto-increment integers
- Routes are evaluated in order; put most specific routes first
- Every form must have a fallback route (catch-all)
- Routers (nested form references) are flattened during evaluation
- The `enrichFormWithMigrationData()` call handles backward compatibility for form schema changes
- Platform requests can force org slug via `x-cal-force-slug` header

## Dependencies

- `react-awesome-query-builder` - conditional logic builder and evaluator
- `packages/features/routing-trace/` - routing decision tracking
- `packages/features/attributes/` - org-level attribute definitions and assignments
- `packages/lib/raqb/` - RAQB evaluation utilities (`evaluateRaqbLogic`, `jsonLogic`)
- `packages/app-store/routing-forms/` - core routing form logic (app store pattern)

## Gotchas

- Routing forms live in both `packages/features/routing-forms/` (server logic, repositories) and `packages/app-store/routing-forms/` (client components, route processing). The split follows the cal.com app store pattern
- `findMatchingRoute` is a client-safe function (marked `"use client"`) but is also called server-side
- CRM routing (`fetchCrm` parameter) adds latency; it can be disabled
- The `formFillerId` + `formId` unique constraint prevents duplicate submissions from the same filler
- `routedToBookingUid` is unique, meaning one form response can only map to one booking
- When no team members match attribute logic, a `fallbackAction` may be used instead of the primary action
- The `isBookingDryRun` flag (via `cal.isBookingDryRun=true` param) skips persistence and trace saving

## Related Concepts

- [Event Types](./event-types.md) - routing targets
- [Organizations and Teams](./organizations-and-teams.md) - org attributes for member matching
- [Workflows and Automations](./workflows-and-automations.md) - `FORM_SUBMITTED` / `FORM_SUBMITTED_NO_EVENT` triggers
