# Accessibility baseline and verification

This document tracks the screen-reader-focused baseline for the dashboard app and how we verify it.

## Route baseline matrix

| Route | Landmarks | Primary heading | Async / status | Notable widgets |
| ----- | --------- | ----------------- | -------------- | ---------------- |
| `/login` | `main#main-content` | `h1` (app name) | Loading `role="status"`; auth errors `role="alert"` | GitHub sign-in |
| `/` (dashboard) | Skip link, `nav` (sidebar), `main#main-content`, `header` | `h1` Dashboard | Environment banner `role="status"` | Metrics / cards |
| `/projects` | Same shell | `h1` Projects | — | Project cards |
| `/projects/[id]` | Same shell | `h1` project name | Tab panels | Tabs, tables, charts, dialogs |
| `/account` | Same shell | `h1` Account | — | Forms / profile |
| `/billing` | Same shell | `h1` Billing | — | Plan / Stripe |
| `/admin` | Same shell | `h1` Admin | — | Tables, metrics |

**Definition of done (screen readers):** Each page exposes a single clear `main` region (via skip link on first tab), primary navigation is a `nav` landmark, async work and toasts are announced, interactive controls have stable names, data tables have captions where helpful, and time-series charts include a text/table equivalent.

## Prioritized gaps addressed in code

1. **Shell:** Skip link, named `main`, sidebar `nav` regions, header account menu label.
2. **Feedback:** Loading states, toasts (`aria-live`), login errors.
3. **Data:** Table captions; chart section + screen-reader data table for time series.
4. **Semantics:** Heading levels in MCP catalog sections; error boundaries use `main` + `lang` on global error.

## Manual screen reader smoke checklist

1. From cold load on `/login`, press Tab once — hear “Skip to main content”; activate and confirm focus moves to main content.
2. Sign in (or use existing session); confirm sidebar is announced as navigation and primary items are reachable.
3. Open the header avatar menu — trigger has an accessible name including who is signed in.
4. Trigger a toast (e.g. copy URL) — message is announced.
5. Open a project → Overview → confirm MCP catalog tables and chart region are navigable; locate the screen-reader summary/table for metrics.
6. Induce or open an error state (e.g. `app/error.tsx`) — message is clear and actions are labeled.

## Automated checks

Vitest + jsdom tests cover the skip link target and toast live-region behavior (see `components/a11y/skip-to-main.test.tsx`, `components/ui/toaster.a11y.test.tsx`). Expand these as new patterns are added.
