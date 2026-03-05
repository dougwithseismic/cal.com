# Organizations and Teams

> Multi-tenancy architecture where organizations are parent teams, teams are children, and users belong via memberships with role-based access.

## Overview

Cal.com uses a unified `Team` model for both organizations and teams. An organization is a `Team` with `isOrganization: true` and `parentId: null`. Sub-teams have `parentId` set to the organization's ID. Users belong to teams/orgs through `Membership` records with roles (MEMBER, ADMIN, OWNER). Organizations control domains, branding, user profiles, and feature access. The `Profile` model connects users to organizations with organization-scoped usernames.

## Key Locations

| Path | Purpose |
|------|---------|
| `packages/prisma/schema.prisma` (line ~569) | `Team` model (used for both orgs and teams) |
| `packages/prisma/schema.prisma` (line ~720) | `OrganizationSettings` model |
| `packages/prisma/schema.prisma` (line ~760) | `Membership` model |
| `packages/prisma/schema.prisma` (line ~546) | `Profile` model (org-scoped user identity) |
| `packages/prisma/schema.prisma` (line ~2816) | `Role` model (custom RBAC roles) |
| `packages/features/ee/organizations/repositories/OrganizationRepository.ts` | Org CRUD operations |
| `packages/features/ee/organizations/lib/orgDomains.ts` | Domain/subdomain resolution |
| `packages/features/ee/organizations/lib/getBrand.ts` | Organization branding resolution |
| `packages/features/ee/organizations/lib/getBookerUrlServer.ts` | Booker URL with org domain |
| `packages/features/ee/organizations/context/provider.ts` | React context for org data |
| `packages/features/ee/organizations/di/` | Dependency injection containers |
| `packages/trpc/server/routers/viewer/organizations/` | Org-related tRPC handlers |
| `packages/trpc/server/routers/viewer/teams/` | Team-related tRPC handlers |

## Patterns

### Organization-Team Hierarchy
**Where:** `packages/prisma/schema.prisma:600-602`
**How it works:** The `Team` model uses a self-referential relation to create the org-team hierarchy:

```prisma
parentId  Int?
parent    Team?  @relation("organization", fields: [parentId], references: [id], onDelete: Cascade)
children  Team[] @relation("organization")
```

- `isOrganization: true` + `parentId: null` = Organization
- `isOrganization: false` + `parentId: <orgId>` = Sub-team within an organization
- `isOrganization: false` + `parentId: null` = Standalone team (no org)

The `orgUsers` relation (`User[] @relation("scope")`) links users directly to an organization scope.

### Membership and Roles
**Where:** `packages/prisma/schema.prisma:760-775`
**How it works:** Users connect to teams/orgs through `Membership`:

```prisma
model Membership {
  teamId               Int
  userId               Int
  accepted             Boolean        @default(false)
  role                 MembershipRole
  customRoleId         String?
  customRole           Role?
  disableImpersonation Boolean        @default(false)
}

enum MembershipRole {
  MEMBER
  ADMIN
  OWNER
}
```

- `accepted: false` indicates a pending invitation
- `customRoleId` links to the `Role` model for custom RBAC roles
- `disableImpersonation` prevents org admins from impersonating this member

### Custom RBAC Roles
**Where:** `packages/prisma/schema.prisma:2816-2831`
**How it works:** Organizations can define custom roles with granular permissions:

```prisma
model Role {
  id          String           @id @default(cuid())
  name        String
  teamId      Int?             // null for global roles
  permissions RolePermission[]
  type        RoleType         @default(CUSTOM)
  @@unique([name, teamId])
}
```

Custom roles are scoped to a team/org via `teamId`. Permissions are stored in a separate `RolePermission` table linked to roles.

### Profile Model (Org-Scoped Identity)
**Where:** `packages/prisma/schema.prisma:546-566`
**How it works:** When a user joins an organization, a `Profile` record is created to give them an org-scoped username:

```prisma
model Profile {
  userId         Int
  organizationId Int
  username       String
  @@unique([userId, organizationId])
  @@unique([username, organizationId])
}
```

A user can have multiple profiles across different organizations. The profile's `username` may differ from the user's base username. Event types can be linked to a profile via `profileId`.

### Organization Creation
**Where:** `packages/features/ee/organizations/repositories/OrganizationRepository.ts:28-74`
**How it works:** `createWithExistingUserAsOwner()` creates an organization, then creates a `Profile` for the owner and a `Membership` with `OWNER` role:

```typescript
const organization = await this.create(orgData);
const ownerProfile = await createAProfileForAnExistingUser({
  user: { id: owner.id, email: owner.email, currentUsername: owner.nonOrgUsername },
  organizationId: organization.id,
});
await this.prismaClient.membership.create({
  data: {
    userId: owner.id,
    role: MembershipRole.OWNER,
    accepted: true,
    teamId: organization.id,
  },
});
```

### Organization Domain Resolution
**Where:** `packages/features/ee/organizations/lib/orgDomains.ts:17-60`
**How it works:** Organizations get subdomains like `acme.cal.com`. The `getOrgSlug()` function extracts the org slug from the hostname by removing the known base domain:

```typescript
export function getOrgSlug(hostname: string, forcedSlug?: string) {
  if (SINGLE_ORG_SLUG) return SINGLE_ORG_SLUG;
  const currentHostname = ALLOWED_HOSTNAMES.find(/* ... */);
  const slug = hostname.replace(`.${currentHostname}`, "");
  return slug;
}
```

- `SINGLE_ORG_SLUG` env var forces single-org mode (entire instance is one org)
- `RESERVED_SUBDOMAINS` prevents conflicts with system subdomains
- `getOrgFullOrigin()` constructs the full URL: `https://{slug}.{subdomainSuffix()}`

### Org Domain Config
**Where:** `packages/features/ee/organizations/lib/orgDomains.ts:62-137`
**How it works:** `getOrgDomainConfig()` returns `{ isValidOrgDomain, currentOrgDomain }` based on the request hostname. Platform requests (identified by `x-cal-client-id` header) can force a slug via `x-cal-force-slug` header.

### Booker URL Resolution
**Where:** `packages/features/ee/organizations/lib/getBookerUrlServer.ts:4-7`
**How it works:** Booking page URLs are org-aware. If the event belongs to a team in an org, the booker URL uses the org's domain:

```typescript
export const getBookerBaseUrl = async (organizationId: number | null) => {
  const orgBrand = await getBrand(organizationId);
  return orgBrand?.fullDomain ?? WEBSITE_URL;
};
```

### Organization Branding
**Where:** `packages/features/ee/organizations/lib/getBrand.ts`
**How it works:** `getBrand()` fetches org metadata (logo, slug, domain) and constructs the full domain URL. Platform orgs explicitly return `null` for branding since they don't have public-facing domains.

### Organization Settings
**Where:** `packages/prisma/schema.prisma:720-740`
**How it works:** `OrganizationSettings` stores org-level configuration:

```prisma
model OrganizationSettings {
  organizationId                      Int     @unique
  isOrganizationConfigured            Boolean @default(false)
  isOrganizationVerified              Boolean @default(false)
  orgAutoAcceptEmail                  String   // domain for auto-accepting members
  lockEventTypeCreationForUsers       Boolean @default(false)
  adminGetsNoSlotsNotification        Boolean @default(false)
  isAdminReviewed                     Boolean @default(false)
  isAdminAPIEnabled                   Boolean @default(false)
  allowSEOIndexing                    Boolean @default(false)
  orgProfileRedirectsToVerifiedDomain Boolean @default(false)
}
```

- `orgAutoAcceptEmail`: Email domain (e.g., "acme.com") for auto-accepting new members
- `lockEventTypeCreationForUsers`: Prevents non-admin members from creating event types
- `isAdminReviewed`: Required for sensitive operations like impersonation

### Team Event Types vs Individual Event Types
**Where:** `packages/prisma/schema.prisma:180-181`
**How it works:** An event type belongs to either a user (`userId`) or a team (`teamId`):

- Individual: `userId` is set, `teamId` is null, `schedulingType` is null
- Team: `teamId` is set, `schedulingType` is ROUND_ROBIN/COLLECTIVE/MANAGED
- Team event types use the `Host` model to assign members
- Team event types with `assignAllTeamMembers: true` auto-include all team members

### Team Booking Limits
**Where:** `packages/prisma/schema.prisma:641-643`
**How it works:** Teams can have their own `bookingLimits` (separate from event type limits). When `includeManagedEventsInLimits` is true, bookings from managed child event types also count toward the team limit.

### Team Features
**Where:** `packages/prisma/schema.prisma:639`
**How it works:** The `TeamFeatures` relation (feature flags) controls which premium features are enabled for a team/org. Features are assigned via admin tools.

## Conventions

- Organizations are always `Team` records with `isOrganization: true`
- The `slug` field is unique across teams and organizations
- Platform organizations (`isPlatform: true`) don't have public domains or branding
- `SINGLE_ORG_SLUG` env var enables single-organization mode for self-hosted instances
- Organization members have their `organizationId` set on the `User` model via the `scope` relation
- Team member attributes (for routing) are stored via `AttributeToUser` linked through `Membership`

## Dependencies

- `packages/features/ee/` - organization features are enterprise-only (ee)
- `packages/features/users/repositories/UserRepository.ts` - enriches users with profile data
- `packages/features/profile/` - profile creation and management
- `packages/lib/constants.ts` - `WEBSITE_URL`, `WEBAPP_URL`, `ALLOWED_HOSTNAMES`, `RESERVED_SUBDOMAINS`

## Gotchas

- The `Team` model is overloaded: check `isOrganization` and `parentId` to determine if it is an org, sub-team, or standalone team
- A team with `parentId: null` and `managedOrganization` set has a special meaning (see schema comment line ~648)
- `orgAutoAcceptEmail` on `OrganizationSettings` determines the domain for auto-accepting new member signups
- Platform orgs (`isPlatform: true`) have different behavior: no branding, no public domain, use OAuth clients
- `isAdminReviewed` must be true for org admin impersonation to work (security gate)
- User `username` can differ from their `Profile.username` within an organization
- Deleting an organization cascades to all sub-teams, memberships, and event types

## Related Concepts

- [Event Types](./event-types.md) - team event types and scheduling types
- [Availability and Scheduling](./availability-and-scheduling.md) - aggregated availability for teams
- [Routing Forms](./routing-forms.md) - org-level routing and attribute-based team member matching
- [Workflows and Automations](./workflows-and-automations.md) - org-wide workflow activation
