"use client";

import { toastError, toastSuccess } from "@/lib/toast";

export function buildMcpJsonConfig(mcpUrl: string, apiKey: string) {
  return JSON.stringify(
    {
      mcpServers: {
        MyContextProtocol: {
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
