import { stubNextPublicApiUrlUnset } from "@/lib/testing/stub-public-env";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { NextRequest } from "next/server";

describe("POST /api/billing/checkout-session", () => {
  const fetchMock = vi.fn<typeof fetch>();

  beforeEach(() => {
    vi.resetModules();
    fetchMock.mockReset();
    vi.stubGlobal("fetch", fetchMock);
  });

  afterEach(() => {
    vi.unstubAllGlobals();
    vi.unstubAllEnvs();
  });

  it("forwards cookie, origin, referer, and body to backend", async () => {
    vi.stubEnv("NEXT_PUBLIC_API_URL", "http://api.test");
    const { POST } = await import("./route");
    const payload = { interval: "month" as const };
    fetchMock.mockResolvedValueOnce({
      ok: true,
      status: 200,
      headers: new Headers({ "content-type": "application/json" }),
      arrayBuffer: () =>
        Promise.resolve(new TextEncoder().encode(JSON.stringify({ url: "https://stripe.test" })).buffer),
    } as Response);

    const res = await POST(
      new NextRequest("http://app.test/api/billing/checkout-session", {
        method: "POST",
        headers: {
          cookie: "vapor-session=abc",
          origin: "http://app.test",
          referer: "http://app.test/billing",
          "content-type": "application/json",
        },
        body: JSON.stringify(payload),
      })
    );

    expect(res.status).toBe(200);
    await expect(res.json()).resolves.toEqual({ url: "https://stripe.test" });
    expect(fetchMock).toHaveBeenCalledWith("http://api.test/billing/checkout-session", {
      method: "POST",
      headers: {
        Cookie: "vapor-session=abc",
        "Content-Type": "application/json",
        Origin: "http://app.test",
        Referer: "http://app.test/billing",
      },
      body: JSON.stringify(payload),
    });
  });

  it("defaults to localhost:8080 when NEXT_PUBLIC_API_URL is unset", async () => {
    stubNextPublicApiUrlUnset();
    const { POST } = await import("./route");
    fetchMock.mockResolvedValueOnce({
      ok: true,
      status: 200,
      headers: new Headers({ "content-type": "application/json" }),
      arrayBuffer: () => Promise.resolve(new ArrayBuffer(0)),
    } as Response);

    await POST(
      new NextRequest("http://app.test/api/billing/checkout-session", { method: "POST" })
    );
    expect(fetchMock).toHaveBeenCalledWith(
      "http://localhost:8080/billing/checkout-session",
      expect.anything()
    );
  });
});
