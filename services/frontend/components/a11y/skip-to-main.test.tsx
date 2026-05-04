import { describe, expect, it } from "vitest";
import { renderToStaticMarkup } from "react-dom/server";
import { SkipToMainContent } from "./skip-to-main";
import { MAIN_CONTENT_ID } from "@/lib/a11y";

describe("SkipToMainContent", () => {
  it("links to the shared main content id", () => {
    const html = renderToStaticMarkup(<SkipToMainContent />);
    expect(html).toContain(`href="#${MAIN_CONTENT_ID}"`);
    expect(html).toMatch(/skip to main content/i);
  });
});
