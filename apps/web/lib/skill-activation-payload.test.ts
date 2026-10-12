import { describe, expect, it } from "vitest";
import { skillActivationPayload } from "./skill-activation-payload";

describe("metadata activation payload", () => {
  it("sends all activation arrays for a legacy skill without canonical metadata", () => {
    expect(skillActivationPayload(null, "explicit", [])).toEqual({
      mode: "explicit", intents: [], events: [], tags: [], examples: [],
    });
  });
  it("preserves event triggers, tags and examples while editing visible fields", () => {
    const canonical = JSON.stringify({ activation: {
      mode: "event", intents: ["old intent"], events: ["test_failed"], tags: ["swift"], examples: ["Review a failing test"],
    } });
    expect(skillActivationPayload(canonical, "intent", ["new intent"])).toEqual({
      mode: "intent", intents: ["new intent"], events: ["test_failed"], tags: ["swift"], examples: ["Review a failing test"],
    });
  });
  it("fills omitted arrays without replacing existing values", () => {
    expect(skillActivationPayload('{"activation":{"events":["task_completed"]}}', "event", []).events).toEqual(["task_completed"]);
    expect(skillActivationPayload("{}", "always", []).tags).toEqual([]);
  });
});
