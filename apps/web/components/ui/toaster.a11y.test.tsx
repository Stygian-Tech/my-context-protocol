/** @vitest-environment jsdom */

import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { createRoot } from "react-dom/client";
import { act } from "react";

afterEach(() => {
  vi.useRealTimers();
});

beforeEach(() => {
  vi.resetModules();
});

describe("Toaster accessibility", () => {
  it("renders toast copy in a live region", async () => {
    vi.useFakeTimers({ shouldAdvanceTime: true });
    const { Toaster } = await import("@/components/ui/toaster");
    const { toastSuccess } = await import("@/lib/toast");

    const host = document.createElement("div");
    document.body.appendChild(host);
    const root = createRoot(host);

    await act(async () => {
      root.render(<Toaster />);
      toastSuccess("Settings saved");
    });

    const region = host.querySelector('[aria-label="Notifications"]');
    expect(region).toBeTruthy();
    expect(region?.getAttribute("role")).toBe("region");

    const status = host.querySelector('[role="status"][aria-live="polite"]');
    expect(status?.textContent).toContain("Settings saved");

    await act(async () => {
      root.unmount();
    });
    host.remove();
  });
});
