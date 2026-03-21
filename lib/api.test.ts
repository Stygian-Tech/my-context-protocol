import { describe, expect, it, vi } from "vitest";
import { ApiError, apiFetch } from "./api";

describe("api", () => {
  it("ApiError exposes status", () => {
    const err = new ApiError("nope", 404, { x: 1 });
    expect(err.status).toBe(404);
    expect(err.name).toBe("ApiError");
  });

  it("apiFetch throws ApiError on non-ok JSON", async () => {
    const json = { error: "bad" };
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue({
        ok: false,
        status: 422,
        statusText: "Unprocessable",
        headers: new Headers({ "content-type": "application/json" }),
        json: () => Promise.resolve(json),
      } as Response)
    );
    await expect(apiFetch("/x")).rejects.toMatchObject({
      status: 422,
    });
    vi.unstubAllGlobals();
  });

  it("apiFetch returns JSON on ok", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue({
        ok: true,
        status: 200,
        headers: new Headers({ "content-type": "application/json" }),
        json: () => Promise.resolve({ a: 1 }),
      } as Response)
    );
    await expect(apiFetch("/ok")).resolves.toEqual({ a: 1 });
    vi.unstubAllGlobals();
  });
});
