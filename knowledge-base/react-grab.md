# React Grab

## What Is It

[React Grab](https://github.com/aidenybai/react-grab) (by Aiden Bai) lets you click any element in a running React app and instantly get its exact source location (file path, line number, component stack). Designed to bridge the gap between visual UI and source code, especially for AI-assisted coding workflows.

## How It's Used in Cal.com

Loaded as a global script in **development mode only** via `apps/web/app/layout.tsx`:

```tsx
{process.env.NODE_ENV === "development" && (
  <Script
    src="//unpkg.com/react-grab/dist/index.global.js"
    crossOrigin="anonymous"
    strategy="beforeInteractive"
    data-options='{"activationKey":"Meta+c"}'
  />
)}
```

- Activation: `Meta+C` (Cmd+C / Win+C)
- Only in dev — never shipped to production
- No npm dependency — loaded from unpkg CDN

## Two Modes

### 1. Clipboard Mode (default, what we use)
- Click an element after activating with `Meta+C`
- React Grab walks up the component tree, collects component names and source locations
- Copies formatted context to clipboard
- Paste into any AI coding assistant (Claude Code, Cursor, etc.)

### 2. Agent Mode (optional, not configured here)
- Requires an adapter package (e.g., `@react-grab/claude-code`)
- Sends element context + prompt directly to a coding agent via local server
- Agent edits files directly; status streams back to browser
- Supported adapters: `@react-grab/claude-code`, `@react-grab/cursor`, `@react-grab/opencode`, `@react-grab/codex`, `@react-grab/gemini`, `@react-grab/amp`, `@react-grab/droid`

## Why It Matters for AI Workflows

- Eliminates the "search phase" — agent gets exact file paths and line numbers instead of grepping
- Benchmarks show ~3x speedup on UI tasks (fewer tool calls, fewer files read)
- Particularly useful for large codebases like Cal.com where components are spread across many packages

## Potential Enhancement

If we wanted the direct agent mode, we'd install `@react-grab/claude-code` and run a local server. For now, clipboard mode is sufficient — paste the context and the agent reads the referenced files directly.

## References

- [GitHub repo](https://github.com/aidenybai/react-grab)
- [Official site](https://www.react-grab.com/)
- [Agent mode docs](https://www.react-grab.com/blog/agent)
- [Intro / benchmarks](https://www.react-grab.com/blog/intro)
