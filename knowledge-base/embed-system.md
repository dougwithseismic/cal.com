# Embed System

> Cal.com's embed system enables booking pages to be embedded into third-party websites via inline, modal, or floating button modes, using an iframe-based architecture with a postMessage protocol for communication between host page and embedded content.

## Overview

The embed system consists of three packages: `embed-core` (the main SDK loaded on the host page and the iframe-side code), `embed-react` (React component wrapper), and `embed-snippet` (lightweight loader script). The host page loads `embed.js` which creates iframes pointing to the cal.com booking pages. Communication happens via `window.postMessage` with a namespaced event system (`CAL:{namespace}:{event}`).

## Key Locations

| Path | Purpose |
|------|---------|
| `packages/embeds/embed-core/src/embed.ts` | Host-side SDK: creates iframes, manages modals/inline embeds |
| `packages/embeds/embed-core/src/embed-iframe.ts` | Iframe-side code: handles messages from parent, fires events |
| `packages/embeds/embed-core/src/sdk-action-manager.ts` | Event system for typed embed events |
| `packages/embeds/embed-core/src/sdk-event.ts` | Singleton SDK action manager instance |
| `packages/embeds/embed-core/src/types.ts` | TypeScript types for embed config, styles, booker state |
| `packages/embeds/embed-core/src/constants.ts` | Timing constants for modal prerendering and slot staleness |
| `packages/embeds/embed-core/src/Inline/inline.ts` | `Inline` custom element (Web Component) for inline embeds |
| `packages/embeds/embed-core/src/ModalBox/ModalBox.ts` | `ModalBox` custom element for modal embeds |
| `packages/embeds/embed-core/src/FloatingButton/FloatingButton.ts` | `FloatingButton` custom element for floating button trigger |
| `packages/embeds/embed-core/src/EmbedElement.ts` | Base class for all embed custom elements |
| `packages/embeds/embed-core/src/embed-iframe/lib/embedStore.ts` | Shared state store for iframe-side embed |
| `packages/embeds/embed-core/src/embed-iframe/lib/utils.ts` | Iframe utility functions (readiness checks, dimension tracking) |
| `packages/embeds/embed-core/src/embed-iframe/react-hooks.ts` | React hooks for embed-aware components |
| `packages/embeds/embed-core/src/ui/cssVarsMap.ts` | CSS variable mapping for theming |
| `packages/embeds/embed-core/src/lib/domUtils.ts` | DOM utilities for scrollable ancestor detection |
| `packages/embeds/embed-core/vite.config.js` | Build configuration for embed-core |
| `packages/embeds/embed-react/src/Cal.tsx` | React `<Cal>` component for inline embedding |
| `packages/embeds/embed-react/src/useEmbed.ts` | Hook to load embed SDK dynamically |
| `packages/embeds/embed-snippet/src/index.ts` | Embed snippet loader (the JS code users paste) |

## Patterns

### Embed Lifecycle Overview
**How it works:** The embed lifecycle follows these stages:
1. Host page includes the embed snippet or uses `embed-react`
2. Snippet creates a `Cal` global object with a command queue
3. `embed.js` is loaded asynchronously, processes queued commands
4. `Cal("inline", { ... })` or `Cal("modal", { ... })` creates an iframe
5. Iframe loads the cal.com booking page with embed query params
6. Iframe-side code (`embed-iframe.ts`) initializes and fires `__iframeReady`
7. Parent receives `__iframeReady`, sends `parentKnowsIframeReady` back
8. Iframe fires `linkReady` when content is loaded and dimensions are known
9. Parent removes loader and makes iframe visible

### The Embed Snippet (Loader)
**Where:** `packages/embeds/embed-snippet/src/index.ts`
**How it works:** A minimal, self-contained function that creates the global `Cal` function. Before the SDK loads, `Cal()` calls queue arguments in `cal.q`. Once `embed.js` loads, queued commands are replayed. Namespace support allows multiple embed instances on one page.
**Example:**
```typescript
export default function EmbedSnippet(url = EMBED_LIB_URL) {
  (function (C, A, L) {
    let d = C.document;
    C.Cal = C.Cal || function () {
      let cal = C.Cal;
      if (!cal.loaded) {
        cal.ns = {};
        cal.q = cal.q || [];
        d.head.appendChild(d.createElement("script")).src = A;
        cal.loaded = true;
      }
      if (arguments[0] === L) { // "init"
        const api = function () { api.q.push(arguments); };
        const namespace = arguments[1];
        api.q = api.q || [];
        if (typeof namespace === "string") {
          cal.ns[namespace] = cal.ns[namespace] || api;
        }
      }
      cal.q.push(arguments);
    };
  })(window, url, "init");
  return window.Cal;
}
```

### Inline Embed (Web Component)
**Where:** `packages/embeds/embed-core/src/Inline/inline.ts`
**How it works:** The `Inline` class extends `EmbedElement` (a custom HTML element). It uses Shadow DOM for style isolation. The element observes a `loading` attribute that transitions through states: loading (shows skeleton), done (hides loader), failed (shows error message).
**Example:**
```typescript
export class Inline extends EmbedElement {
  static get observedAttributes() { return ["loading"]; }
  constructor() {
    super({ isModal: false, getSkeletonData });
    this.attachShadow({ mode: "open" });
    this.shadowRoot.innerHTML = `<style>${window.Cal.__css}</style>...`;
  }
}
```

### Modal Embed (Web Component)
**Where:** `packages/embeds/embed-core/src/ModalBox/ModalBox.ts`
**How it works:** The `ModalBox` class manages a modal overlay with states: `loading`, `loaded`, `closed`, `failed`, `has-message`, `prerendering`, `reopened`. It handles Escape key and backdrop clicks for closing, and locks `document.body.style.overflow` while open. Modal prerendering allows iframes to be loaded in the background before the user clicks.
**Example state transitions:**
- `prerendering` -> iframe loads hidden, fires `linkPrerendered`
- User clicks -> state becomes `loading` -> iframe connects -> `loaded` -> modal opens
- `closed` -> modal hides, body overflow restored
- `reopened` -> shows without reloading

### Floating Button
**Where:** `packages/embeds/embed-core/src/FloatingButton/FloatingButton.ts`
**How it works:** A custom element that renders a floating action button with configurable text, color, position (bottom-left/bottom-right), and icon visibility. Clicking it opens the modal embed. All configuration is driven by `data-*` attributes observed via `observedAttributes`.

### Message Protocol (Host <-> Iframe)
**Where:** `packages/embeds/embed-core/src/embed-iframe.ts` (iframe side), `packages/embeds/embed-core/src/embed.ts` (host side)
**How it works:** Communication uses `window.postMessage` with messages shaped as `{ originator: "CAL", method: string, arg: any }`.

**Parent -> Iframe methods (via `interfaceWithParent`):**
- `ui(config)` -- Apply theme, styles, CSS variables, color scheme
- `parentKnowsIframeReady()` -- Acknowledge iframe is ready, trigger `linkReady`
- `connect({ config, params })` -- Update prerendered embed with new booking config
- `__reloadInitiated()` -- Signal that a reload is happening

**Iframe -> Parent events (via `SdkActionManager`):**
- `__iframeReady` -- Iframe initialized, ready for messages
- `__dimensionChanged` -- Content dimensions changed, parent adjusts iframe size
- `linkReady` -- Content fully loaded, parent removes loader
- `linkFailed` -- Page load error
- `bookingSuccessfulV2` -- Booking created
- `rescheduleBookingSuccessfulV2` -- Booking rescheduled
- `bookingCancelled` -- Booking cancelled
- `bookerReady` -- Booker with slots loaded
- `__closeIframe` -- Request to close modal
- `__routeChanged` -- URL changed within iframe
- `__scrollByDistance` -- Request parent to scroll

### Event System (SdkActionManager)
**Where:** `packages/embeds/embed-core/src/sdk-action-manager.ts`
**How it works:** Fully typed event system using `CustomEvent`. Events are namespaced as `CAL:{namespace}:{eventName}`. The wildcard `*` event fires for all events. Events are dispatched on `window` and forwarded to parent via `postMessage`.
**Example:**
```typescript
export class SdkActionManager {
  fire<T extends keyof EventDataMap>(name: T, data: EventDataMap[T]) {
    const fullName = this.getFullActionName(name); // "CAL:ns:eventName"
    const detail = { type: name, namespace: this.namespace, fullType: fullName, data };
    _fireEvent(fullName, detail);
    _fireEvent(this.getFullActionName("*"), detail); // wildcard
  }
}
```

### React Embed Component
**Where:** `packages/embeds/embed-react/src/Cal.tsx`
**How it works:** The `<Cal>` component loads the embed SDK via `useEmbed()` hook and calls `Cal("inline", { ... })` on mount. It renders a `<div>` that the SDK uses as the embed container. Supports namespaces for multiple instances.
**Example:**
```tsx
const Cal = function Cal(props: CalProps) {
  const { calLink, calOrigin, namespace = "", config, initConfig = {}, embedJsUrl } = props;
  const Cal = useEmbed(embedJsUrl);
  const ref = useRef<HTMLDivElement>(null);
  useEffect(() => {
    if (!Cal || initializedRef.current || !ref.current) return;
    Cal("init", namespace, { ...initConfig, origin: calOrigin });
    Cal.ns[namespace]("inline", { elementOrSelector: ref.current, calLink, config });
  }, [Cal, calLink, config, namespace]);
  return <div ref={ref} />;
};
```

### How Embed Builds Are Produced
**Where:** `packages/embeds/embed-core/vite.config.js`
**How it works:** Vite builds `embed.ts` into `embed.js` wrapped in an IIFE. The output is placed directly into `apps/web/public/embed/` so it's served at `/embed/embed.js` by the web app. CSS is inlined as strings (imported with `?inline` suffix) for use in Shadow DOM. A preview HTML page is built alongside for development.
**Example:**
```javascript
build: {
  rollupOptions: {
    input: {
      preview: path.resolve(__dirname, "preview.html"),
      embed: path.resolve(__dirname, "src/embed.ts"),
    },
    plugins: [{
      generateBundle: (code, bundle) => {
        bundle["embed.js"].code = `!function(){${bundle["embed.js"].code}}()`;
      },
    }],
    output: {
      entryFileNames: "[name].js",
      dir: "../../../apps/web/public/embed",
    },
  },
}
```

## Conventions

- All embed custom elements use Shadow DOM for style isolation
- CSS is imported as inline strings (e.g., `import css from "./embed.css?inline"`)
- Namespace format: `CAL:{namespace}:{event}` -- empty namespace results in `CAL::{event}`
- The `embedType` query param identifies the embed mode (inline, modal, popup)
- Prerendering uses `prerender=true` and `cal.skipSlotsFetch=true` query params
- The `isEmbed()` global function is used throughout cal.com code to detect embed context
- Theme classes: `cal-element-embed-light`, `cal-element-embed-dark`

## Dependencies

- Vite -- Build tool for the embed bundle
- No runtime dependencies -- the embed snippet and SDK are self-contained
- `@calcom/embed-core` -- peer dependency for `embed-react`
- `react`, `react-dom` -- peer dependencies for `embed-react`

## Gotchas

- The embed SDK cannot import `WEBAPP_URL` from `@calcom/lib/constants` because it would pull in server-side code. It uses `import.meta.env` variables instead.
- Safari uses `setTimeout` instead of `requestAnimationFrame` for dimension polling due to rendering differences.
- If a page is opened in `top === window` (not in an iframe), the embed SDK shows the page normally and skips initialization.
- Modal prerendering has timing thresholds: slots become stale after 1 minute (`EMBED_MODAL_IFRAME_SLOT_STALE_TIME`), full iframe reload after 15 minutes (`EMBED_MODAL_IFRAME_FORCE_RELOAD_THRESHOLD_MS`).
- The `connect()` method is for transitioning prerendered embeds to active state -- it updates query params and triggers slot re-fetch.

## Related Concepts

- [Platform SDK and Atoms](./platform-sdk-atoms.md) -- atoms also embed booking UI but via React components
- [Booking Flow](./booking-flow.md) -- the booking pages that run inside the embed iframe
