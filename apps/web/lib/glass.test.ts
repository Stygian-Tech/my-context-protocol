import { describe, expect, it } from "vitest";
import {
  GLASS_CHROME_BACKDROP_BLUR_CLASSES,
  glassEffectClasses,
  glassSurfaceClasses,
} from "./glass";

describe("glassSurfaceClasses", () => {

  it("pins chrome backdrop blur to one token (env banner + peek sidebar)", () => {
    expect(glassEffectClasses("subtle")).toBe(GLASS_CHROME_BACKDROP_BLUR_CLASSES);
    expect(GLASS_CHROME_BACKDROP_BLUR_CLASSES).toContain(
      "supports-backdrop-filter:backdrop-blur-[5rem]"
    );
    expect(glassEffectClasses("elevated")).toContain("supports-backdrop-filter:backdrop-blur-xl");
  });
  it("returns a subtle shared glass recipe for content surfaces", () => {
    const classes = glassSurfaceClasses("subtle");

    expect(classes).toContain("border");
    expect(classes).toContain("supports-backdrop-filter:backdrop-blur-[5rem]");
    expect(classes).toContain("bg-background/42");
  });

  it("uses a stronger recipe for elevated floating surfaces", () => {
    const classes = glassSurfaceClasses("elevated");

    expect(classes).toContain("supports-backdrop-filter:backdrop-blur-xl");
    expect(classes).toContain("bg-background/55");
    expect(classes).toContain("shadow-lg");
  });

  it("keeps default chrome between subtle and elevated", () => {
    const classes = glassSurfaceClasses();

    expect(classes).toContain("supports-backdrop-filter:backdrop-blur-md");
    expect(classes).toContain("bg-background/48");
    expect(classes).toContain("shadow-sm");
  });
});
