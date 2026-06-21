/** @vitest-environment jsdom */

import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { act } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { CustomDomainSection } from "./custom-domain-section";
import {
  fetchCustomDomain,
  verifyProjectCustomDomain,
} from "@/lib/projects-api";

vi.mock("@/lib/projects-api", () => ({
  fetchCustomDomain: vi.fn(),
  setProjectCustomDomain: vi.fn(),
  verifyProjectCustomDomain: vi.fn(),
}));

const initialStatus = {
  hostname: "mcp.example.com",
  verified: true,
  verification_token: null,
  instructions: null,
  fly_ownership_verification_record_name: "_fly-ownership.mcp.example.com",
  fly_ownership_verification_record_value: "fly-token",
  certificate_status: "pending" as const,
  certificate_message: "Fly certificate provisioning is pending.",
};

const issuedStatus = {
  ...initialStatus,
  certificate_status: "issued" as const,
  certificate_message: "Fly edge TLS certificate is issued.",
};

function deferred<T>() {
  let resolve: (value: T) => void = () => {};
  const promise = new Promise<T>((innerResolve) => {
    resolve = innerResolve;
  });
  return { promise, resolve };
}

async function waitFor(assertion: () => void) {
  const started = Date.now();
  let lastError: unknown;
  while (Date.now() - started < 1000) {
    try {
      assertion();
      return;
    } catch (error) {
      lastError = error;
      await act(async () => {
        await new Promise((resolve) => setTimeout(resolve, 10));
      });
    }
  }
  throw lastError;
}

describe("CustomDomainSection", () => {
  let host: HTMLDivElement;
  let root: Root;
  let queryClient: QueryClient;

  beforeEach(() => {
    vi.mocked(fetchCustomDomain).mockResolvedValue(initialStatus);
    vi.mocked(verifyProjectCustomDomain).mockResolvedValue(issuedStatus);
    queryClient = new QueryClient({
      defaultOptions: {
        queries: { retry: false },
        mutations: { retry: false },
      },
    });
    host = document.createElement("div");
    document.body.appendChild(host);
    root = createRoot(host);
  });

  afterEach(async () => {
    await act(async () => {
      root.unmount();
    });
    host.remove();
    queryClient.clear();
    vi.clearAllMocks();
  });

  it("shows DNS and TLS check phases while refresh is running", async () => {
    const check = deferred<typeof issuedStatus>();
    vi.mocked(verifyProjectCustomDomain).mockReturnValue(check.promise);

    await act(async () => {
      root.render(
        <QueryClientProvider client={queryClient}>
          <CustomDomainSection projectId="project-1" />
        </QueryClientProvider>,
      );
    });

    await waitFor(() => {
      expect(host.textContent).toContain("Refresh DNS/TLS");
    });

    const button = Array.from(host.querySelectorAll("button")).find(
      (candidate) => candidate.textContent?.includes("Refresh DNS/TLS"),
    );

    await act(async () => {
      button?.click();
    });

    await waitFor(() => {
      expect(verifyProjectCustomDomain).toHaveBeenCalledWith("project-1");
      expect(host.textContent).toContain("Checking DNS and TLS");
      expect(host.textContent).toContain("DNS TXT verification:");
      expect(host.textContent).toContain("Fly ownership TXT:");
      expect(host.textContent).toContain("CNAME routing:");
      expect(host.textContent).toContain("Fly TLS certificate:");
      expect(host.textContent).toContain("requesting status");
    });

    await act(async () => {
      check.resolve(issuedStatus);
      await check.promise;
    });
  });

  it("renders the returned TLS status and message after refresh", async () => {
    await act(async () => {
      root.render(
        <QueryClientProvider client={queryClient}>
          <CustomDomainSection projectId="project-1" />
        </QueryClientProvider>,
      );
    });

    await waitFor(() => {
      expect(host.textContent).toContain("Refresh DNS/TLS");
    });

    const button = Array.from(host.querySelectorAll("button")).find(
      (candidate) => candidate.textContent?.includes("Refresh DNS/TLS"),
    );

    await act(async () => {
      button?.click();
    });

    await waitFor(() => {
      expect(host.textContent).toContain("Latest DNS/TLS check");
      expect(host.textContent).toContain("TLS issued");
      expect(host.textContent).toContain("Fly edge TLS certificate is issued.");
    });
  });
});
