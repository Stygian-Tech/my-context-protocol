import { describe, expect, it } from "vitest";
import { glassEffectClasses, glassSurfaceClasses } from "./glass";

describe("glassSurfaceClasses", () => {

  it("exposes blur-only helpers for tinted surfaces like the env banner", () => {
    expect(glassEffectClasses("subtle")).toContain("supports-backdrop-filter:backdrop-blur-sm");
    expect(glassEffectClasses("elevated")).toContain("supports-backdrop-filter:backdrop-blur-xl");
  });
  it("returns a subtle shared glass recipe for content surfaces", () => {
    const classes = glassSurfaceClasses("subtle");

    expect(classes).toContain("border");
    expect(classes).toContain("supports-backdrop-filter:backdrop-blur-sm");
    expect(classes).toContain("bg-background/72");
  });

  it("uses a stronger recipe for elevated floating surfaces", () => {
    const classes = glassSurfaceClasses("elevated");

    expect(classes).toContain("supports-backdrop-filter:backdrop-blur-xl");
    expect(classes).toContain("bg-background/88");
    expect(classes).toContain("shadow-lg");
  });

  it("keeps default chrome between subtle and elevated", () => {
    const classes = glassSurfaceClasses();

    expect(classes).toContain("supports-backdrop-filter:backdrop-blur-md");
    expect(classes).toContain("bg-background/80");
    expect(classes).toContain("shadow-sm");
  });
});
