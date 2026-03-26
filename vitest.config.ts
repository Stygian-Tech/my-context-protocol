import { defineConfig } from "vitest/config";
import path from "path";

const isCi = Boolean(process.env.CI && process.env.CI !== "false");

/** Keep reports focused on code we exercise in tests (excludes shadcn/ui shells). Widen as you add app/component tests. */
const coverageInclude = [
  "lib/**/*.{ts,tsx}",
  "proxy.ts",
  "app/api/**/*.{ts,tsx}",
];

const coverageExclude = [
  "**/*.{test,spec}.{ts,tsx}",
  "**/*.config.{ts,mts,mjs}",
  "lib/types.ts",
  "next-env.d.ts",
];

export default defineConfig({
  test: {
    environment: "node",
    // Vercel + GitHub Actions set CI=1 / CI=true; cap workers on shared builders.
    maxWorkers: isCi ? "50%" : undefined,
    pool: "forks",
    include: ["**/*.{test,spec}.{ts,tsx}"],
    exclude: ["node_modules", ".next", "coverage", "dist"],
    reporters: isCi ? ["default", "github-actions"] : ["default"],
    coverage: {
      provider: "v8",
      reporter: isCi
        ? ["text", "text-summary"]
        : ["text", "text-summary", "html"],
      include: coverageInclude,
      exclude: coverageExclude,
    },
    // Use jsdom only for React component tests (*.test.tsx).
    environmentMatchGlobs: [
      ["**/*.test.tsx", "jsdom"],
      ["components/**/*.test.tsx", "jsdom"],
    ],
  },
  resolve: {
    alias: {
      "@": path.resolve(__dirname, "."),
    },
  },
});
