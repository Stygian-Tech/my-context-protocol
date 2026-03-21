import path from "node:path";
import { defineConfig } from "vitest/config";

export default defineConfig({
  plugins: [],
  test: {
    environment: "node",
    include: ["**/*.test.ts"],
  },
  resolve: {
    alias: {
      "@": path.resolve(__dirname, "./"),
    },
  },
});
