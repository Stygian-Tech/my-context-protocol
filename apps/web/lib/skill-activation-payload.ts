type ActivationMode = "always" | "intent" | "event" | "explicit";

/** Preserve activation fields that the metadata form does not expose. */
export function skillActivationPayload(canonicalJson: string | null | undefined, mode: ActivationMode, intents: string[]) {
  let activation: Record<string, unknown> = {};
  if (canonicalJson) {
    const document = JSON.parse(canonicalJson);
    activation = document.activation ?? {};
  }
  return {
    mode,
    intents,
    events: activation.events as string[] | undefined ?? [],
    tags: activation.tags as string[] | undefined ?? [],
    examples: activation.examples as string[] | undefined ?? [],
  };
}
