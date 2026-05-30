import { afterEach, describe, expect, it, vi } from "vitest";

const { post } = vi.hoisted(() => ({ post: vi.fn() }));

vi.mock("./api", () => ({
  api: { post },
}));

import { createCheckoutSession, createPortalSession } from "./billing-api";

describe("billing-api", () => {
  afterEach(() => {
    post.mockReset();
  });

  it("createCheckoutSession posts with body", async () => {
    post.mockResolvedValueOnce({ url: "https://checkout.stripe.com/x" });
    const out = await createCheckoutSession({ interval: "month", success_path: "/ok" });
    expect(out.url).toBe("https://checkout.stripe.com/x");
    expect(post).toHaveBeenCalledWith("/billing/checkout-session", {
      interval: "month",
      success_path: "/ok",
    });
  });

  it("createCheckoutSession sends empty object when omitted", async () => {
    post.mockResolvedValueOnce({ url: "u" });
    await createCheckoutSession();
    expect(post).toHaveBeenCalledWith("/billing/checkout-session", {});
  });

  it("createPortalSession posts", async () => {
    post.mockResolvedValueOnce({ url: "https://billing.stripe.com/p" });
    const out = await createPortalSession();
    expect(out.url).toBe("https://billing.stripe.com/p");
    expect(post).toHaveBeenCalledWith("/billing/portal-session");
  });
});
