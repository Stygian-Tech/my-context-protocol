import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

beforeEach(() => {
  vi.resetModules();
  vi.useFakeTimers();
  vi.stubGlobal(
    "window",
    {
      setTimeout: (fn: () => void, ms?: number) =>
        globalThis.setTimeout(fn, ms ?? 0) as unknown as number,
    } as Window
  );
});

afterEach(() => {
  vi.unstubAllGlobals();
  vi.useRealTimers();
});

describe("toast", () => {
  it("subscribe receives pushes and prunes after timeout", async () => {
    const { subscribeToToasts, toastSuccess, toastError } = await import("./toast");

    const seen: { id: number; message: string; variant: string }[][] = [];
    const unsub = subscribeToToasts((t) => seen.push(t));

    toastSuccess("ok");
    toastError("bad");

    expect(seen.at(-1)?.length).toBe(2);
    expect(seen.at(-1)?.map((x) => x.message)).toEqual(["ok", "bad"]);

    await vi.advanceTimersByTimeAsync(3000);
    expect(seen.at(-1)?.length).toBe(0);

    unsub();
  });
});
