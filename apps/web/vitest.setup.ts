/**
 * Enables React `act()` in Vitest jsdom so client components that schedule updates
 * (e.g. `useEffect`) don't warn during tests.
 *
 * Worker `NODE_ENV` / `NODE_OPTIONS` are normalized in `vitest.config.ts` so the
 * `react` package resolves to a build that includes `act` (see `lib/testing/vitest-worker-env.ts`).
 */
;(globalThis as unknown as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT =
  true;
