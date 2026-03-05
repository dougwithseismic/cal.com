# UI Components

> How the shared UI component library is structured and used across Cal.com.

## Overview

`packages/ui` is Cal.com's shared design system built with React and Tailwind CSS. It provides 40+ component categories (buttons, forms, dialogs, tables, navigation, etc.) using `class-variance-authority` for variant management. Components are imported via path-based exports in `package.json`.

## Key Locations

| Path | Purpose |
|------|---------|
| `packages/ui/` | UI package root |
| `packages/ui/components/` | All UI components organized by category |
| `packages/ui/classNames.ts` | Utility for className merging |
| `packages/ui/styles/` | Global CSS styles |
| `packages/ui/package.json` | Export map for all components |
| `packages/ui/components/form/` | Form components (inputs, select, checkbox, etc.) |
| `packages/ui/components/button/` | Button variants |
| `packages/ui/components/dialog/` | Modal dialogs |
| `packages/ui/components/icon/` | Icon system |
| `packages/ui/components/layout/` | Layout primitives |
| `packages/ui/components/navigation/` | Navigation components |
| `packages/ui/components/table/` | Table components |

## Patterns

### Component Import Pattern
**Where:** `packages/ui/package.json` (exports map)
**How it works:** Components are imported via path-based exports, not a single barrel file. Each component category has its own export path.
**Example:**
```ts
// Importing UI components
import { Button } from "@calcom/ui/components/button";
import { Dialog, DialogContent } from "@calcom/ui/components/dialog";
import { Input, Label } from "@calcom/ui/components/form";
import { Icon } from "@calcom/ui/components/icon";
import { Tooltip } from "@calcom/ui/components/tooltip";
import { Alert } from "@calcom/ui/components/alert";
import { Loader } from "@calcom/ui/components/skeleton";
```

### Component Categories

| Category | Path | Key Components |
|----------|------|----------------|
| `button` | `components/button/` | Button, LinkIconButton, SplitButton |
| `form` | `components/form/` | Inputs, Select, Checkbox, Switch, DatePicker, Wizard |
| `dialog` | `components/dialog/` | Dialog, DialogContent, DialogTrigger |
| `dropdown` | `components/dropdown/` | Dropdown menu |
| `table` | `components/table/` | Table, TableNew |
| `icon` | `components/icon/` | Icon (with IconSprites) |
| `avatar` | `components/avatar/` | Avatar |
| `badge` | `components/badge/` | Badge |
| `toast` | `components/toast/` | Toast notifications |
| `tooltip` | `components/tooltip/` | Tooltip |
| `skeleton` | `components/skeleton/` | Loader, Skeleton |
| `alert` | `components/alert/` | Alert |
| `card` | `components/card/` | Card |
| `navigation` | `components/navigation/` | Navigation components |
| `layout` | `components/layout/` | Layout primitives |
| `empty-screen` | `components/empty-screen/` | Empty state |
| `sheet` | `components/sheet/` | Side sheet/drawer |
| `popover` | `components/popover/` | Popover |
| `breadcrumb` | `components/breadcrumb/` | Breadcrumb |
| `top-banner` | `components/top-banner/` | Top notification banner |
| `command` | `components/command/` | Command palette |
| `editor` | `components/editor/` | Rich text editor |
| `segmented-control` | `components/segmented-control/` | Segmented control |

### Button Component (CVA Pattern)
**Where:** `packages/ui/components/button/Button.tsx`
**How it works:** Uses `class-variance-authority` (CVA) for type-safe variant management. Supports color, size, loading states, icons, and tooltip.
**Example:**
```tsx
// packages/ui/components/button/Button.tsx:1-34
import type { VariantProps } from "class-variance-authority";
import { cva } from "class-variance-authority";

type InferredVariantProps = VariantProps<typeof buttonClasses>;

export type ButtonBaseProps = {
  onClick?: (event: React.MouseEvent<HTMLElement, MouseEvent>) => void;
  CustomStartIcon?: React.ReactNode;
  StartIcon?: IconName;
  EndIcon?: IconName;
  tooltip?: string | React.ReactNode;
  disabled?: boolean;
  flex?: boolean;
} & Omit<InferredVariantProps, "color"> & { color?: ButtonColor; };
```

### Form Components
**Where:** `packages/ui/components/form/`
**How it works:** Form components include inputs, selects, checkboxes, switches, date pickers, and form wizards. Many integrate with react-hook-form via `useFormContext`.

Form sub-directories:
```
form/
  inputs/              # Text inputs, multi-option input
    Input.tsx          # Base input component
    HintOrErrors.tsx   # Form field error display
    MultiOptionInput.tsx
  select/              # Select dropdowns
  checkbox/            # Checkbox components
  color-picker/        # Color picker
  date-range-picker/   # Date range selection
  datepicker/          # Single date picker
  step/                # Step indicator
  switch/              # Toggle switch
  toggleGroup/         # Toggle group
  wizard/              # Multi-step wizard
```

### Form Integration with react-hook-form
**Where:** `packages/ui/components/form/inputs/Input.tsx`
**How it works:** Form components use `useFormContext` from react-hook-form to automatically connect to the nearest `FormProvider`.
**Example:**
```tsx
// packages/ui/components/form/inputs/Input.tsx uses:
import { useFormContext } from "react-hook-form";
```

### Icon System
**Where:** `packages/ui/components/icon/`
**How it works:** Icons use a sprite-based system (`IconSprites` loaded in root layout). Components reference icons by name via the `IconName` type.

### Address Components
**Where:** `packages/ui/components/address/`
**How it works:** Specialized address input fields for location forms.

## Conventions

- Components use Tailwind CSS for styling (no CSS modules or styled-components)
- `class-variance-authority` (CVA) for variant-based styling on complex components
- `@calcom/ui/classNames` for className merging (wrapper around `clsx`/`twMerge`)
- Each component category has an `index.ts` that re-exports public components
- Path-based imports only (`@calcom/ui/components/<category>`) -- no barrel file at root
- Components are functional, using `forwardRef` where needed
- Biome for linting (`yarn lint` in ui package)

## Dependencies

- **Styling:** Tailwind CSS, class-variance-authority
- **Icons:** Custom icon system with sprites
- **Forms:** react-hook-form integration
- **Links:** next/link for navigation
- **Used by:** `apps/web/`, `packages/features/*/components/`, `packages/platform/atoms/`

## Gotchas

- Do not use a single barrel import from `@calcom/ui` -- use specific paths like `@calcom/ui/components/button`
- The `dynamicIconImports.tsx` file is excluded from Biome formatting
- Some components have test files colocated (e.g., `button.test.tsx`)
- The `test-setup.tsx` in `packages/ui/components/` provides test utilities
- `sideEffects: false` is set in package.json, enabling tree-shaking

## Related Concepts

- [React Hooks](./react-hooks.md) -- form hooks that connect to UI form components
- [Next.js Routing](./next-js-routing.md) -- pages that render UI components
- [Feature Architecture](./feature-architecture.md) -- feature components use @calcom/ui
