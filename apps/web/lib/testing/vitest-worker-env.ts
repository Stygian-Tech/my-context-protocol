/**
 * Environment overrides for Vitest workers on hosts that run the test command with
 * `NODE_ENV=production` and/or `NODE_OPTIONS` `--conditions=react-server` (common on
 * Vercel/Next). See `vitest.config.ts`.
 *
 * Does not fully parse shell-quoted NODE_OPTIONS; targets typical CI flag shapes.
 */

function stripReactServerFromConditionsValue(value: string): string | null {
  const parts = value
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean)
    .filter((c) => c !== "react-server");
  if (parts.length === 0) return null;
  return parts.join(",");
}

/** Remove `react-server` from `--conditions=…` / `-C=…` / space-separated forms. */
export function stripReactServerConditionsFromNodeOptions(raw: string): string {
  const tokens = raw.trim().split(/\s+/).filter(Boolean);
  const out: string[] = [];

  for (let i = 0; i < tokens.length; i++) {
    const t = tokens[i];
    if (t === undefined) continue;

    if (t === "--conditions" || t === "-C") {
      const value = tokens[i + 1];
      if (value === undefined) {
        out.push(t);
        continue;
      }
      i++;
      const next = stripReactServerFromConditionsValue(value);
      if (next) {
        out.push(t, next);
      }
      continue;
    }

    if (t.startsWith("--conditions=")) {
      const value = t.slice("--conditions=".length);
      const next = stripReactServerFromConditionsValue(value);
      if (next) out.push(`--conditions=${next}`);
      continue;
    }

    if (t.startsWith("-C=")) {
      const value = t.slice("-C=".length);
      const next = stripReactServerFromConditionsValue(value);
      if (next) out.push(`-C=${next}`);
      continue;
    }

    out.push(t);
  }

  return out.join(" ").trim();
}

/** Subset of `process.env` read by Vitest worker normalization. */
export interface VitestWorkerEnvInput {
  NODE_ENV?: string | undefined;
  NODE_OPTIONS?: string | undefined;
}

/**
 * Variables to merge into Vitest worker `process.env` (see Vitest `test.env`).
 */
export function buildVitestWorkerEnv(env: VitestWorkerEnvInput): Record<string, string> {
  const out: Record<string, string> = {};

  if (env.NODE_ENV === "production") {
    out.NODE_ENV = "development";
  }

  if (typeof env.NODE_OPTIONS === "string") {
    const stripped = stripReactServerConditionsFromNodeOptions(env.NODE_OPTIONS);
    const normalized = env.NODE_OPTIONS.trim().replace(/\s+/g, " ");
    if (stripped !== normalized) {
      out.NODE_OPTIONS = stripped;
    }
  }

  return out;
}
