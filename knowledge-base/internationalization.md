# Internationalization (i18n)

> Cal.com uses `next-i18next` with i18next under the hood, supporting 35+ locales with a single `common` namespace per locale.

## Overview

Translations are organized as JSON files under `packages/i18n/locales/<locale>/common.json`. The source locale is English (`en`). Server-side code uses `getTranslation()` from `@calcom/i18n/server`, while client-side React components use the `useLocale()` hook. The locale list is defined in the root `i18n.json` configuration file, which is consumed by both the next-i18next config and the Lingo.dev schema for translation management.

## Key Locations

| Path | Purpose |
|------|---------|
| `i18n.json` | Root config defining source locale and all target locales |
| `packages/i18n/next-i18next.config.js` | next-i18next configuration (default locale, fallbacks) |
| `packages/i18n/server.ts` | Server-side translation loading with caching |
| `packages/i18n/locales/en/common.json` | English source translations (the reference file) |
| `packages/i18n/locales/<locale>/common.json` | Per-locale translation files |
| `packages/lib/hooks/useLocale.ts` | Client-side `useLocale()` hook for React components |
| `packages/lib/i18n.ts` | Locale options helper for dropdowns/selectors |

## Patterns

### Server-Side Translation
**Where:** `packages/i18n/server.ts`
**How it works:** `getTranslation(locale, namespace)` creates a cached i18next instance per locale. Translations are loaded via dynamic import and merged with English as fallback. Results are cached in memory Maps.

**Example:**
```typescript
import { getTranslation } from "@calcom/i18n/server";

const t = await getTranslation("fr", "common");
const translated = t("booking_confirmed"); // French translation
```

### English Fallback Merge
**Where:** `packages/i18n/server.ts`
**How it works:** All locale translations are merged with English translations as a base, ensuring missing keys fall back to English rather than showing raw keys.

**Example:**
```typescript
export function mergeWithEnglishFallback(localeTranslations: Record<string, string>) {
  return {
    ...englishTranslations,  // English first as fallback
    ...localeTranslations,   // Locale overrides
  };
}
```

### Client-Side Translation via useLocale Hook
**Where:** `packages/lib/hooks/useLocale.ts`
**How it works:** The `useLocale()` hook checks for App Router context first (server-rendered translations), then falls back to client-side i18next. It supports both Pages Router and App Router patterns.

**Example:**
```typescript
import { useLocale } from "@calcom/lib/hooks/useLocale";

function MyComponent() {
  const { t, isLocaleReady } = useLocale();
  return <h1>{t("welcome_message")}</h1>;
}
```

### next-i18next Configuration
**Where:** `packages/i18n/next-i18next.config.js`
**How it works:** Reads from root `i18n.json` to get locale list. Sets English as default, `zh` falls back to `zh-CN`, and locale files are loaded from `./locales` directory.

**Example:**
```javascript
const config = {
  i18n: {
    defaultLocale: i18n.locale.source,       // "en"
    locales: i18n.locale.targets.concat([i18n.locale.source]),
  },
  fallbackLng: {
    default: ["en"],
    zh: ["zh-CN"],
  },
  reloadOnPrerender: process.env.NODE_ENV !== "production",
  localePath: path.resolve(__dirname, "./locales"),
};
```

### Translation Key Conventions
**Where:** `packages/i18n/locales/en/common.json`
**How it works:** Keys use snake_case. Interpolation uses `{{variable}}`. Pluralization uses i18next's `_one`/`_other` suffix convention. Nested `$t()` references are supported.

**Example:**
```json
{
  "trial_days_left": "You have $t(day, {\"count\": {{days}} }) left on your pro trial",
  "day_one": "{{count}} day",
  "day_other": "{{count}} days",
  "reset_password_subject": "{{appName}}: Reset password instructions"
}
```

### Locale Options for UI Dropdowns
**Where:** `packages/lib/i18n.ts`
**How it works:** Generates locale option objects using `Intl.DisplayNames` for human-readable locale labels.

**Example:**
```typescript
export const localeOptions = locales.map((locale) => ({
  value: locale,
  label: new Intl.DisplayNames(locale, { type: "language" }).of(locale) || "",
}));
```

## How to Add New Translations

1. Add the new translation key to `packages/i18n/locales/en/common.json`
2. The key should use `snake_case` naming
3. Use `{{variable}}` for interpolation
4. For plurals, add both `key_one` and `key_other` variants
5. Other locale files will fall back to English until translated
6. To add a new locale, add the locale code to the `targets` array in `i18n.json` and create `packages/i18n/locales/<code>/common.json`

## Conventions

- Single namespace: `common` is the only supported namespace (enforced in `server.ts`)
- Keys are `snake_case`
- English is always the source of truth
- All translations go in the flat `common.json` -- there are no nested namespace files
- The `zh` locale auto-maps to `zh-CN`
- 35+ locales supported including RTL languages (Arabic, Hebrew)

## Dependencies

- `i18next` - Core translation library
- `next-i18next` - Next.js integration
- `react-i18next` - React hooks integration
- `lingo.dev` - Translation management (configured via `i18n.json` schema)

## Gotchas

- The `common` namespace is the only supported namespace. Passing other namespaces falls back to `common`
- Server-side translations are cached in memory Maps (`translationCache`, `i18nInstanceCache`), so changes to locale files require a restart in production
- The `useLocale()` hook warns in console when used outside App Router context
- The `zh` locale is automatically remapped to `zh-CN` in server-side translation loading

## Related Concepts

- [Cron and Background Jobs](./cron-and-background-jobs.md) - Tasker has tasks for translating event type data (`translateEventTypeData`, `translateWorkflowStepData`)
