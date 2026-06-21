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

const copyTextToClipboard = vi.hoisted(() => vi.fn());

vi.mock("@/lib/projects-api", () => ({
  fetchCustomDomain: vi.fn(),
  setProjectCustomDomain: vi.fn(),
  verifyProjectCustomDomain: vi.fn(),
}));

vi.mock("@/lib/clipboard", () => ({
  copyTextToClipboard,
}));

const initialStatus = {
  hostname: "mcp.example.com",
  verified: true,
  verification_token: null,
  verification_record_name: null,
  instructions: null,
  fly_ownership_verification_record_name: "_fly-ownership.mcp.example.com",
  fly_ownership_verification_record_value: "fly-token",
  fly_a_record_values: null,
  fly_aaaa_record_values: null,
  fly_cname_record_value: null,
  certificate_status: "pending" as const,
  certificate_message: "Fly certificate provisioning is pending.",
};

const issuedStatus = {
  ...initialStatus,
  certificate_status: "issued" as const,
  certificate_message: "Fly edge TLS certificate is issued.",
};

const dnsRequiredStatus = {
  ...initialStatus,
  instructions: [
    "Add an A record on mcp.example.com pointing to: 66.241.125.232",
    "Add an AAAA record on mcp.example.com pointing to: 2a09:8280:1::1",
    "Add a CNAME record on mcp.example.com pointing to: gateway.fly.dev",
  ].join("\n"),
  fly_a_record_values: ["66.241.125.232"],
  fly_aaaa_record_values: ["2a09:8280:1::1"],
  fly_cname_record_value: "gateway.fly.dev",
  certificate_message: "Fly certificate validation is waiting on DNS records.",
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
    copyTextToClipboard.mockResolvedValue(undefined);
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
      expect(host.textContent).toContain("Fly routing:");
      expect(host.textContent).toContain("Fly TLS certificate:");
      expect(host.textContent).toContain("requesting status");
    });

    await act(async () => {
      check.resolve(issuedStatus);
      await check.promise;
    });
  });

  it("shows project verification TXT on a non-conflicting record name", async () => {
    vi.mocked(fetchCustomDomain).mockResolvedValue({
      ...initialStatus,
      verified: false,
      verification_token: "project-token",
      verification_record_name: "_mcp-verify.mcp.example.com",
      fly_ownership_verification_record_name: null,
      fly_ownership_verification_record_value: null,
      certificate_status: null,
      certificate_message: null,
    });

    await act(async () => {
      root.render(
        <QueryClientProvider client={queryClient}>
          <CustomDomainSection projectId="project-1" />
        </QueryClientProvider>,
      );
    });

    await waitFor(() => {
      expect(host.textContent).toContain("Required verification records");
      expect(host.textContent).toContain("_mcp-verify.mcp.example.com");
      expect(host.textContent).toContain("project-token");
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

  it("renders Fly DNS requirements returned by the TLS check", async () => {
    vi.mocked(verifyProjectCustomDomain).mockResolvedValue(dnsRequiredStatus);

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
      expect(host.textContent).toContain("DNS records");
      expect(host.textContent).toContain("Required verification records");
      expect(host.textContent).toContain("TXT");
      expect(host.textContent).toContain("_fly-ownership.mcp.example.com");
      expect(host.textContent).toContain("fly-token");
      expect(host.textContent).toContain("Routing options");
      expect(host.textContent).toContain("Copying one option disables the other to avoid invalid DNS records.");
      expect(host.textContent).toContain("Option 1: A/AAAA records");
      expect(host.textContent).toContain("Copy A/AAAA");
      expect(host.textContent).toContain("A");
      expect(host.textContent).toContain("66.241.125.232");
      expect(host.textContent).toContain("AAAA");
      expect(host.textContent).toContain("2a09:8280:1::1");
      expect(host.textContent).toContain("Option 2: CNAME record");
      expect(host.textContent).toContain("Copy CNAME");
      expect(host.textContent).toContain("CNAME");
      expect(host.textContent).toContain("gateway.fly.dev");
      expect(host.textContent).toContain("Add an A record on mcp.example.com pointing to: 66.241.125.232");
    });
  });

  it("locks routing to the copied option until the flow is restarted", async () => {
    vi.mocked(verifyProjectCustomDomain).mockResolvedValue(dnsRequiredStatus);

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

    const refresh = Array.from(host.querySelectorAll("button")).find(
      (candidate) => candidate.textContent?.includes("Refresh DNS/TLS"),
    );

    await act(async () => {
      refresh?.click();
    });

    await waitFor(() => {
      expect(host.textContent).toContain("Copy A/AAAA");
      expect(host.textContent).toContain("Copy CNAME");
    });

    const copyAddress = Array.from(host.querySelectorAll("button")).find(
      (candidate) => candidate.textContent?.includes("Copy A/AAAA"),
    );

    await act(async () => {
      copyAddress?.click();
    });

    expect(copyTextToClipboard).toHaveBeenCalledWith(
      "A\tmcp.example.com\t66.241.125.232\nAAAA\tmcp.example.com\t2a09:8280:1::1",
      {
        success: "A/AAAA records copied to clipboard",
        error: "Could not copy DNS records",
      },
    );
    expect(host.textContent).toContain("Selected: A/AAAA records");

    const copyCnameDisabled = Array.from(host.querySelectorAll("button")).find(
      (candidate) => candidate.textContent?.includes("Copy CNAME"),
    );
    expect(copyCnameDisabled?.hasAttribute("disabled")).toBe(true);

    const restart = Array.from(host.querySelectorAll("button")).find(
      (candidate) => candidate.textContent?.includes("Restart DNS flow"),
    );

    await act(async () => {
      restart?.click();
    });

    const copyCnameEnabled = Array.from(host.querySelectorAll("button")).find(
      (candidate) => candidate.textContent?.includes("Copy CNAME"),
    );
    expect(copyCnameEnabled?.hasAttribute("disabled")).toBe(false);
  });

  it("does not repeat the certificate message in the instructions", async () => {
    vi.mocked(verifyProjectCustomDomain).mockResolvedValue({
      ...dnsRequiredStatus,
      instructions: [
        "Fly certificate validation is waiting on DNS records.",
        "Add an A record on mcp.example.com pointing to: 66.241.125.232",
      ].join("\n"),
      certificate_message: "Fly certificate validation is waiting on DNS records.",
    });

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
      expect(host.textContent).toContain("Add an A record on mcp.example.com pointing to: 66.241.125.232");
    });

    const messageMatches =
      host.textContent?.match(/Fly certificate validation is waiting on DNS records\./g) ?? [];
    expect(messageMatches).toHaveLength(1);
  });
});
