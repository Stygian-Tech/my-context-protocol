/**
 * Enables React `act()` in Vitest jsdom so client components that schedule updates
 * (e.g. `useEffect`) don't warn during tests.
 */
;(globalThis as unknown as { IS_REACT_ACT_ENVIRONMENT?: boolean }).IS_REACT_ACT_ENVIRONMENT =
  true;
