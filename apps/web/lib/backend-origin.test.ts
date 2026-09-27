import { afterEach, describe, expect, it, vi } from "vitest";
import { getBackendOrigin } from "./backend-origin";

afterEach(() => {
  vi.unstubAllEnvs();
});

describe("getBackendOrigin", () => {
  it("prefers the server-only backend URL and removes a trailing slash", () => {
    vi.stubEnv("BACKEND_URL", "http://gateway.railway.internal:8080/");
    vi.stubEnv("API_ORIGIN", "https://api-origin.example");
    vi.stubEnv("NEXT_PUBLIC_API_URL", "https://public-api.example");

    expect(getBackendOrigin()).toBe("http://gateway.railway.internal:8080");
  });

  it("falls back through API_ORIGIN, the public URL, and localhost", () => {
    vi.stubEnv("BACKEND_URL", "");
    vi.stubEnv("API_ORIGIN", "https://api-origin.example/");
    vi.stubEnv("NEXT_PUBLIC_API_URL", "https://public-api.example/");
    expect(getBackendOrigin()).toBe("https://api-origin.example");

    vi.stubEnv("API_ORIGIN", "");
    expect(getBackendOrigin()).toBe("https://public-api.example");

    vi.stubEnv("NEXT_PUBLIC_API_URL", "");
    expect(getBackendOrigin()).toBe("http://localhost:8080");
  });
});
