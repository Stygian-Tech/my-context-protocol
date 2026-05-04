"use client";

import { toastError, toastSuccess } from "@/lib/toast";

function mcpServerConfigKey(projectSlug?: string | null): string {
  const raw = projectSlug
    ?.trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
  if (raw && raw.length > 0) {
    return `MyContextProtocol_${raw}`;
  }
  return "MyContextProtocol";
}

export function buildMcpJsonConfig(
  mcpUrl: string,
  apiKey: string,
  options?: { projectSlug?: string | null }
) {
  const serverKey = mcpServerConfigKey(options?.projectSlug);
  return JSON.stringify(
    {
      mcpServers: {
        [serverKey]: {
          url: mcpUrl,
          headers: {
            Authorization: `Bearer ${apiKey}`,
          },
        },
      },
    },
    null,
    2
  );
}

/** Same-origin path as MCP POST URL with `/events` for SSE list_changed notifications. */
export function mcpEventsUrl(mcpUrl: string): string {
  const t = mcpUrl.trimEnd();
  return t.endsWith("/") ? `${t}events` : `${t}/events`;
}

export async function copyTextToClipboard(
  text: string,
  messages: {
    success: string;
    error: string;
  }
) {
  try {
    await navigator.clipboard.writeText(text);
    toastSuccess(messages.success);
  } catch {
    toastError(messages.error);
  }
}
