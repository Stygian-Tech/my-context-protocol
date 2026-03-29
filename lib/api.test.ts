import { afterEach, describe, expect, it, vi } from "vitest";
import { ApiError, api, apiFetch, formatApiErrorDetail } from "./api";

afterEach(() => {
  vi.unstubAllGlobals();
  vi.unstubAllEnvs();
});

describe("formatApiErrorDetail", () => {
  it("covers common body shapes", () => {
    expect(formatApiErrorDetail("")).toBe("");
    expect(formatApiErrorDetail(null)).toBe("");
    expect(formatApiErrorDetail("plain")).toBe("plain");
    expect(formatApiErrorDetail({ reason: "r" })).toBe("r");
    expect(formatApiErrorDetail({ error: "e" })).toBe("e");
    expect(formatApiErrorDetail({ message: "m" })).toBe("m");
    expect(formatApiErrorDetail({ other: 1 })).toContain("other");
    const cyclic: Record<string, unknown> = {};
    cyclic.self = cyclic;
    expect(formatApiErrorDetail(cyclic)).toBe("[object Object]");
    expect(formatApiErrorDetail(42)).toBe("42");
  });
});

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
  });

  it("apiFetch uses null error body when JSON parse fails on error response", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue({
        ok: false,
        status: 400,
        statusText: "Bad",
        headers: new Headers({ "content-type": "application/json" }),
        json: () => Promise.reject(new Error("invalid json")),
      } as Response)
    );
    const err = await apiFetch("/bad-json-err").catch((e) => e);
    expect(err).toBeInstanceOf(ApiError);
    expect((err as ApiError).body).toBeNull();
  });

  it("apiFetch throws ApiError on non-ok text body", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue({
        ok: false,
        status: 500,
        statusText: "Err",
        headers: new Headers({ "content-type": "text/plain" }),
        text: () => Promise.resolve("boom"),
      } as Response)
    );
    const err = await apiFetch("/x").catch((e) => e);
    expect(err).toBeInstanceOf(ApiError);
    expect((err as ApiError).body).toBe("boom");
  });

  it("apiFetch returns undefined for 204", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue({
        ok: true,
        status: 204,
        headers: new Headers({}),
      } as Response)
    );
    await expect(apiFetch("/empty")).resolves.toBeUndefined();
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
  });

  it("apiFetch returns text when not JSON", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue({
        ok: true,
        status: 200,
        headers: new Headers({ "content-type": "text/plain" }),
        text: () => Promise.resolve("hello"),
      } as Response)
    );
    await expect(apiFetch("/t")).resolves.toBe("hello");
  });

  it("uses /api base when window is defined", async () => {
    vi.stubGlobal("window", {} as Window);
    const fetchMock = vi.fn().mockResolvedValue({
      ok: true,
      status: 200,
      headers: new Headers({ "content-type": "application/json" }),
      json: () => Promise.resolve({}),
    } as Response);
    vi.stubGlobal("fetch", fetchMock);
    await apiFetch("relative");
    expect(fetchMock).toHaveBeenCalledWith(
      "/api/relative",
      expect.objectContaining({ credentials: "include" })
    );
  });

  it("uses env base URL without window", async () => {
    vi.stubEnv("NEXT_PUBLIC_API_URL", "https://api.test");
    const fetchMock = vi.fn().mockResolvedValue({
      ok: true,
      status: 200,
      headers: new Headers({ "content-type": "application/json" }),
      json: () => Promise.resolve({}),
    } as Response);
    vi.stubGlobal("fetch", fetchMock);
    await apiFetch("/path");
    expect(fetchMock).toHaveBeenCalledWith(
      "https://api.test/path",
      expect.anything()
    );
  });

  it("api shorthands forward methods", async () => {
    const fetchMock = vi.fn().mockResolvedValue({
      ok: true,
      status: 200,
      headers: new Headers({ "content-type": "application/json" }),
      json: () => Promise.resolve({ ok: true }),
    } as Response);
    vi.stubGlobal("fetch", fetchMock);

    await api.get("/g");
    expect(fetchMock.mock.calls[0]?.[1]).toMatchObject({ method: "GET" });

    await api.post("/p", { a: 1 });
    expect(fetchMock.mock.calls[1]?.[1]).toMatchObject({
      method: "POST",
      body: JSON.stringify({ a: 1 }),
    });

    await api.post("/p2");
    expect(fetchMock.mock.calls[2]?.[1]).toMatchObject({
      method: "POST",
      body: undefined,
    });

    await api.put("/u", {});
    expect(fetchMock.mock.calls[3]?.[1]).toMatchObject({
      method: "PUT",
      body: JSON.stringify({}),
    });

    await api.put("/u2");
    expect(fetchMock.mock.calls[4]?.[1]).toMatchObject({
      method: "PUT",
      body: undefined,
    });

    await api.patch("/a", null);
    expect(fetchMock.mock.calls[5]?.[1]).toMatchObject({ method: "PATCH" });

    await api.patch("/a2");
    expect(fetchMock.mock.calls[6]?.[1]).toMatchObject({
      method: "PATCH",
      body: undefined,
    });

    await api.patch("/a3", { patched: true });
    expect(fetchMock.mock.calls[7]?.[1]).toMatchObject({
      method: "PATCH",
      body: JSON.stringify({ patched: true }),
    });

    await api.delete("/d");
    expect(fetchMock.mock.calls[8]?.[1]).toMatchObject({ method: "DELETE" });
  });

  it("defaults API host to localhost:8080 without env or window", async () => {
    vi.stubEnv("NEXT_PUBLIC_API_URL", undefined);
    const fetchMock = vi.fn().mockResolvedValue({
      ok: true,
      status: 200,
      headers: new Headers({ "content-type": "application/json" }),
      json: () => Promise.resolve({}),
    } as Response);
    vi.stubGlobal("fetch", fetchMock);
    await apiFetch("/root");
    expect(fetchMock).toHaveBeenCalledWith(
      "http://localhost:8080/root",
      expect.anything()
    );
  });
});
