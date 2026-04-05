import { describe, expect, it } from "vitest";
import {
  bannerMessage,
  bannerClasses,
  bannerVisible,
  envMismatch,
  parseAppEnv,
  primaryEnvForCopy,
} from "./env-banner";

describe("env-banner", () => {
  it("parseAppEnv defaults invalid to prod", () => {
    expect(parseAppEnv(undefined)).toBe("prod");
    expect(parseAppEnv("staging")).toBe("prod");
  });

  it("parseAppEnv accepts known envs", () => {
    expect(parseAppEnv("local")).toBe("local");
    expect(parseAppEnv(" DEV ")).toBe("dev");
    expect(parseAppEnv("prod")).toBe("prod");
  });

  it("bannerVisible for local or dev on either side", () => {
    expect(bannerVisible("local", null)).toBe(true);
    expect(bannerVisible("prod", "dev")).toBe(true);
    expect(bannerVisible("prod", "prod")).toBe(false);
  });

  it("envMismatch when both set and differ", () => {
    expect(envMismatch("dev", null)).toBe(false);
    expect(envMismatch("dev", "dev")).toBe(false);
    expect(envMismatch("dev", "local")).toBe(true);
  });

  it("bannerMessage copy", () => {
    expect(bannerMessage("local")).toContain("Local");
    expect(bannerMessage("dev")).toContain("Development");
    expect(bannerMessage("prod")).toBe("");
  });

  it("adds backdrop blur to keep banner text readable", () => {
    expect(bannerClasses("local", false)).toContain("supports-backdrop-filter:backdrop-blur-sm");
    expect(bannerClasses("local", false)).toContain("bg-yellow-400/40");
    expect(bannerClasses("dev", false)).toContain("bg-red-500/28");
    expect(bannerClasses("dev", true)).toContain("bg-amber-500/20");
  });

  it("primaryEnvForCopy prefers API non-prod", () => {
    expect(primaryEnvForCopy("prod", "dev")).toBe("dev");
    expect(primaryEnvForCopy("local", null)).toBe("local");
    expect(primaryEnvForCopy("prod", null)).toBe("prod");
    expect(primaryEnvForCopy("prod", "prod")).toBe("prod");
  });
});
