import { afterEach, describe, expect, it, vi } from "vitest";
import { isClientApiLoggingEnabled } from "./client-api-logging";

afterEach(() => {
  vi.unstubAllEnvs();
});

describe("isClientApiLoggingEnabled", () => {
  it("is false in test env by default", () => {
    vi.stubEnv("NODE_ENV", "test");
    vi.stubEnv("NEXT_PUBLIC_CLIENT_API_LOG", undefined);
    vi.stubEnv("VERCEL_ENV", undefined);
    vi.stubEnv("NEXT_PUBLIC_APP_ENV", undefined);
    expect(isClientApiLoggingEnabled()).toBe(false);
  });

  it("is true in test when explicitly enabled", () => {
    vi.stubEnv("NODE_ENV", "test");
    vi.stubEnv("NEXT_PUBLIC_CLIENT_API_LOG", "1");
    expect(isClientApiLoggingEnabled()).toBe(true);
  });

  it("is false when explicitly disabled", () => {
    vi.stubEnv("NODE_ENV", "development");
    vi.stubEnv("NEXT_PUBLIC_CLIENT_API_LOG", "0");
    expect(isClientApiLoggingEnabled()).toBe(false);
  });

  it("is true in development", () => {
    vi.stubEnv("NODE_ENV", "development");
    vi.stubEnv("NEXT_PUBLIC_CLIENT_API_LOG", undefined);
    expect(isClientApiLoggingEnabled()).toBe(true);
  });

  it("is true for Vercel preview", () => {
    vi.stubEnv("NODE_ENV", "production");
    vi.stubEnv("VERCEL_ENV", "preview");
    vi.stubEnv("NEXT_PUBLIC_APP_ENV", "prod");
    vi.stubEnv("NEXT_PUBLIC_CLIENT_API_LOG", undefined);
    expect(isClientApiLoggingEnabled()).toBe(true);
  });

  it("is true when NEXT_PUBLIC_APP_ENV is dev", () => {
    vi.stubEnv("NODE_ENV", "production");
    vi.stubEnv("VERCEL_ENV", "production");
    vi.stubEnv("NEXT_PUBLIC_APP_ENV", "dev");
    expect(isClientApiLoggingEnabled()).toBe(true);
  });
});
