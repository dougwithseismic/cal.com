# Testing Patterns

> How unit, integration, and E2E tests are structured and run in the Cal.com codebase.

## Overview

Cal.com uses Vitest for unit and integration testing, Playwright for E2E testing, and Jest for API v2 (NestJS) tests. Tests run in three Vitest modes (default, integration, timezone) and follow naming conventions to be routed to the correct mode. Mocking uses vitest-fetch-mock and vitest-mock-extended.

## Key Locations

| Path | Purpose |
|------|---------|
| `vitest.config.mts` | Root Vitest configuration |
| `vitest.workspace.ts` | Workspace configuration |
| `packages/testing/src/setupVitest.ts` | Global test setup (mocks, polyfills) |
| `vitest-mocks/` | Static mock files (SVG hashes, CSS) |
| `playwright.config.ts` | Playwright E2E configuration |
| `apps/web/playwright/` | E2E test files |
| `apps/api/v2/jest.config.ts` | API v2 Jest configuration |
| `apps/api/v2/test/` | API v2 test utilities |

## Patterns

### Vitest Configuration
**Where:** `vitest.config.mts`
**How it works:** Uses `jsdom` environment, `@vitejs/plugin-react`, and supports three modes controlled by `VITEST_MODE` env var.
**Example:**
```ts
// vitest.config.mts:28-40
function getTestInclude() {
  if (isPackagedEmbedMode) {
    return ["packages/embeds/**/packaged/**/*.{test,spec}.{ts,js}"];
  }
  if (isIntegrationMode) {
    return ["packages/**/*.integration-test.ts", "apps/**/*.integration-test.ts"];
  }
  if (isTimezoneMode) {
    return ["packages/**/*.timezone.test.ts", "apps/**/*.timezone.test.ts"];
  }
  return ["**/*.{test,spec}.{js,mjs,cjs,ts,mts,cts,jsx,tsx}"];
}
```

Key config details:
```ts
// vitest.config.mts:103-120
test: {
  globals: true,
  silent: true,
  environment: "jsdom",
  setupFiles: ["./packages/testing/src/setupVitest.ts"],
  pool: "forks",
  passWithNoTests: true,
  testTimeout: 500000,
  exclude: [
    "**/node_modules/**",
    "**/dist/**",
    "apps/api/v2/**/*.spec.ts",  // API v2 uses Jest
    "__checks__/**/*.spec.ts",
  ],
}
```

### Test File Naming Conventions

| Pattern | Mode | Example |
|---------|------|---------|
| `*.test.ts` / `*.test.tsx` | Default (unit) | `getLuckyUser.test.ts` |
| `*.integration-test.ts` | Integration | `BookingRepository.integration-test.ts` |
| `*.timezone.test.ts` | Timezone | `useTimesForSchedule.timezone.test.ts` |
| `*.spec.ts` (in `apps/api/v2/`) | Jest (API v2) | API endpoint specs |

### Running Tests

```bash
# All unit tests (TZ=UTC)
yarn test

# Single file
TZ=UTC yarn vitest run path/to/file.test.ts

# Watch mode
yarn tdd

# Integration tests
VITEST_MODE=integration yarn test

# Timezone tests (requires TZ to be set)
TZ=America/New_York VITEST_MODE=timezone yarn test

# E2E tests
yarn test-e2e           # Seeds DB + runs web E2E
yarn e2e                # Web E2E without seeding
yarn e2e:app-store      # App store E2E
yarn e2e:embed          # Embed E2E

# API v2 tests (Jest)
cd apps/api/v2 && yarn test
```

### Global Test Setup
**Where:** `packages/testing/src/setupVitest.ts`
**How it works:** Sets up global mocks and polyfills before all tests run.
**Example:**
```ts
// packages/testing/src/setupVitest.ts:1-32
import matchers from "@testing-library/jest-dom/matchers";
import ResizeObserver from "resize-observer-polyfill";
import { expect, vi } from "vitest";
import createFetchMock from "vitest-fetch-mock";

global.ResizeObserver = ResizeObserver;

// Mock window.matchMedia for jsdom
if (typeof window !== "undefined") {
  Object.defineProperty(window, "matchMedia", {
    writable: true,
    configurable: true,
    value: vi.fn().mockImplementation((query) => ({
      matches: false, media: query, onchange: null,
      addListener: vi.fn(), removeListener: vi.fn(),
      addEventListener: vi.fn(), removeEventListener: vi.fn(),
      dispatchEvent: vi.fn(),
    })),
  });
}

const fetchMocker = createFetchMock(vi);
fetchMocker.enableMocks();
expect.extend(matchers);
```

### Environment Variables for Tests
**Where:** `vitest.config.mts:126-135`
**How it works:** Certain env vars are set before tests start because they are consumed at import time.
**Example:**
```ts
// vitest.config.mts:126-135
process.env.DAILY_API_KEY = "MOCK_DAILY_API_KEY";
process.env.NEXT_PUBLIC_WEBAPP_URL = "http://app.cal.local:3000";
process.env.CALCOM_SERVICE_ACCOUNT_ENCRYPTION_KEY = "UNIT_TEST_ENCRYPTION_KEY";
process.env.STRIPE_PRIVATE_KEY = process.env.STRIPE_PRIVATE_KEY || "sk_test_dummy_unit_test_key";
```

### Mocking Patterns

**vitest-fetch-mock:** Global fetch is mocked in setup. Tests can configure responses.

**vi.mock for modules:** Standard Vitest mocking for module replacements.
```ts
// Example from packages/trpc/server/routers/viewer/teams/inviteMember/__mocks__/
// Mock files are placed in __mocks__/ directories colocated with the source
```

**Calendar service mocking:** The setup file provides a mock `ExchangeCalendarService` class.

### Playwright E2E Configuration
**Where:** `playwright.config.ts`
**How it works:** Runs against `localhost:3000` with Chromium. Uses `Europe/London` timezone. Configures separate projects for web, app-store, embed-core, and embed-react.
**Example:**
```ts
// playwright.config.ts:68-72
const DEFAULT_CHROMIUM = {
  ...devices["Desktop Chrome"],
  timezoneId: "Europe/London",
  storageState: { cookies: [{ url: WEBAPP_URL, name: "calcom-timezone-dialog", value: "1" }] },
};
```

Web server is started automatically:
```ts
// playwright.config.ts:30-40
webServer: [{
  command: "yarn workspace @calcom/web copy-app-store-static && NEXT_PUBLIC_IS_E2E=1 ... yarn workspace @calcom/web start -p 3000",
  port: 3000,
  timeout: 60_000,
}]
```

### API v2 Testing (Jest)
**Where:** `apps/api/v2/jest.config.ts`, `apps/api/v2/test/`
**How it works:** NestJS API v2 uses Jest (not Vitest). Spec files use `*.spec.ts`. These are excluded from the Vitest config.

## Conventions

- All unit tests run with `TZ=UTC` by default (set in `yarn test` script)
- Test files are colocated with source files (not in a separate `__tests__/` at root)
- `__mocks__/` directories are used for module-level mocks
- Integration tests require a real database connection
- Timezone tests require explicit `TZ` env var
- Vitest `globals: true` means `describe`, `it`, `expect`, `vi` are available without imports
- `pool: "forks"` is used for test isolation

## Dependencies

- **Unit/Integration:** Vitest, @vitejs/plugin-react, vitest-fetch-mock, @testing-library/jest-dom, resize-observer-polyfill
- **E2E:** @playwright/test
- **API v2:** Jest (separate config in NestJS app)

## Gotchas

- API v2 tests (`apps/api/v2/**/*.spec.ts`) are explicitly excluded from Vitest -- they run with Jest
- The `__checks__` directory contains monitoring checks, not regular tests
- `INTEGRATION_TEST_MODE` env var is always set to `"true"` in Vitest config to allow server-side imports in jsdom
- Test timeout is very high (500000ms / ~8 minutes) to accommodate slow CI
- Packaged embed tests have their own mode (`VITEST_MODE=packaged-embed`)
- Alias resolution in tests includes mocks for generated files that may not exist in CI

## Related Concepts

- [Monorepo and Tooling](./monorepo-and-tooling.md) -- test scripts in package.json
- [Feature Architecture](./feature-architecture.md) -- test files colocated with features
