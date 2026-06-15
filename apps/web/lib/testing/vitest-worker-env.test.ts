import { describe, expect, it } from "vitest";
import {
  buildVitestWorkerEnv,
  stripReactServerConditionsFromNodeOptions,
} from "./vitest-worker-env";

describe("stripReactServerConditionsFromNodeOptions", () => {
  it("removes --conditions=react-server", () => {
    expect(stripReactServerConditionsFromNodeOptions("--conditions=react-server")).toBe(
      ""
    );
  });

  it("removes react-server from a comma-separated list", () => {
    expect(
      stripReactServerConditionsFromNodeOptions("--conditions=node,react-server")
    ).toBe("--conditions=node");
  });

  it("handles space-separated --conditions value", () => {
    expect(
      stripReactServerConditionsFromNodeOptions("--conditions react-server --require ./x")
    ).toBe("--require ./x");
  });

  it("handles -C=react-server", () => {
    expect(stripReactServerConditionsFromNodeOptions("-C=react-server")).toBe("");
  });

  it("handles space-separated -C react-server", () => {
    expect(stripReactServerConditionsFromNodeOptions("-C react-server")).toBe("");
  });

  it("leaves unrelated flags", () => {
    expect(stripReactServerConditionsFromNodeOptions("--require ./setup.mjs")).toBe(
      "--require ./setup.mjs"
    );
  });
});

describe("buildVitestWorkerEnv", () => {
  it("forces NODE_ENV off production for workers", () => {
    expect(buildVitestWorkerEnv({ NODE_ENV: "production" })).toEqual({
      NODE_ENV: "development",
    });
  });

  it("does not set NODE_ENV when not production", () => {
    expect(buildVitestWorkerEnv({ NODE_ENV: "test" })).toEqual({});
    expect(buildVitestWorkerEnv({})).toEqual({});
  });

  it("strips react-server from NODE_OPTIONS when it changes the string", () => {
    expect(
      buildVitestWorkerEnv({
        NODE_OPTIONS: "--conditions=react-server",
      })
    ).toEqual({ NODE_OPTIONS: "" });
  });

  it("does not emit NODE_OPTIONS when unchanged", () => {
    expect(
      buildVitestWorkerEnv({
        NODE_OPTIONS: "--require ./x",
      })
    ).toEqual({});
  });

  it("combines NODE_ENV and NODE_OPTIONS fixes", () => {
    expect(
      buildVitestWorkerEnv({
        NODE_ENV: "production",
        NODE_OPTIONS: "--conditions=node,react-server",
      })
    ).toEqual({
      NODE_ENV: "development",
      NODE_OPTIONS: "--conditions=node",
    });
  });
});
