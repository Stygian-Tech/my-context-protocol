import { MAIN_CONTENT_ID } from "@/lib/a11y";

/**
 * First focusable control for keyboard / screen reader users; targets {@link MAIN_CONTENT_ID}.
 */
export function SkipToMainContent() {
  return (
    <a href={`#${MAIN_CONTENT_ID}`} className="skip-to-main">
      Skip to Main Content
    </a>
  );
}
