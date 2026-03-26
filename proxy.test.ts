import { describe, expect, it } from "vitest";
import { NextRequest } from "next/server";
import { proxy } from "./proxy";

describe("proxy", () => {
  it("continues the request when auth_token is absent", () => {
    const res = proxy(new NextRequest("http://localhost:3000/dashboard"));
    expect(res.status).toBe(200);
  });

  it("redirects to /api/auth/confirm when auth_token is present", () => {
    const res = proxy(
      new NextRequest("http://localhost:3000/?auth_token=secret&other=1")
    );
    expect(res.status).toBeGreaterThanOrEqual(300);
    expect(res.status).toBeLessThan(400);
    const loc = res.headers.get("location");
    expect(loc).toBeTruthy();
    expect(loc!).toMatch(/\/api\/auth\/confirm\?/);
    expect(loc!).toContain("token=");
    expect(loc!).toContain(encodeURIComponent("secret"));
  });
});
