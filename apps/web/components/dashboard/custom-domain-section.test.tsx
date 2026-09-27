/** @vitest-environment jsdom */

import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { act } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { CustomDomainSection } from "./custom-domain-section";
import { ApiError } from "@/lib/api";
import {
  type CustomDomainStatus,
  fetchCustomDomain,
  setProjectCustomDomain,
  verifyProjectCustomDomain,
} from "@/lib/projects-api";

const copyTextToClipboard = vi.hoisted(() => vi.fn());

vi.mock("@/lib/projects-api", () => ({
  fetchCustomDomain: vi.fn(),
  setProjectCustomDomain: vi.fn(),
  verifyProjectCustomDomain: vi.fn(),
}));

vi.mock("@/lib/clipboard", () => ({ copyTextToClipboard }));

const initialStatus: CustomDomainStatus = {
  hostname: "mcp.example.com",
  verified: true,
  verification_token: null,
  verification_record_name: null,
  instructions: null,
  platform_dns_records: [
    {
      type: "TXT",
      name: "_railway-verify.mcp.example.com",
      value: "railway-token",
      status: "DNS_RECORD_STATUS_PROPAGATED",
      purpose: "OWNERSHIP_VERIFICATION",
    },
    {
      type: "CNAME",
      name: "mcp.example.com",
      value: "gateway.up.railway.app",
      status: "DNS_RECORD_STATUS_REQUIRES_UPDATE",
      purpose: "DNS_RECORD_PURPOSE_TRAFFIC_ROUTE",
    },
  ],
  certificate_status: "pending",
  certificate_message: "Railway TLS certificate provisioning is pending.",
};

const issuedStatus: CustomDomainStatus = {
  ...initialStatus,
  platform_dns_records: initialStatus.platform_dns_records!.map((record) => ({
    ...record,
    status: "DNS_RECORD_STATUS_PROPAGATED",
  })),
  certificate_status: "issued",
  certificate_message: "Railway edge TLS certificate is issued.",
};

function deferred<T>() {
  let resolve: (value: T) => void = () => {};
  const promise = new Promise<T>((innerResolve) => { resolve = innerResolve; });
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
      await act(async () => { await new Promise((resolve) => setTimeout(resolve, 10)); });
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
      defaultOptions: { queries: { retry: false }, mutations: { retry: false } },
    });
    host = document.createElement("div");
    document.body.appendChild(host);
    root = createRoot(host);
  });

  afterEach(async () => {
    await act(async () => { root.unmount(); });
    host.remove();
    queryClient.clear();
    vi.resetAllMocks();
  });

  async function renderSection() {
    await act(async () => {
      root.render(
        <QueryClientProvider client={queryClient}>
          <CustomDomainSection projectId="project-1" />
        </QueryClientProvider>,
      );
    });
    await waitFor(() => { expect(host.textContent).toContain("Hostname:"); });
  }

  function button(label: string) {
    const result = Array.from(host.querySelectorAll("button")).find(
      (candidate) => candidate.textContent?.includes(label),
    );
    expect(result).toBeDefined();
    return result!;
  }

  async function click(label: string) {
    await act(async () => { button(label).click(); });
  }

  async function enterHostname(value: string) {
    const input = host.querySelector("input")!;
    await act(async () => {
      Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value")!.set!.call(input, value);
      input.dispatchEvent(new Event("input", { bubbles: true }));
    });
  }

  it("renders Railway TXT and CNAME requirements without Fly routing choices", async () => {
    await renderSection();
    expect(host.textContent).toContain("Required Railway DNS records");
    expect(host.textContent).toContain("_railway-verify.mcp.example.com");
    expect(host.textContent).toContain("railway-token");
    expect(host.textContent).toContain("gateway.up.railway.app");
    expect(host.textContent).not.toContain("Fly");
    expect(host.textContent).not.toContain("Routing options");
  });

  it("shows each Railway record's status independently of saved project verification", async () => {
    await renderSection();
    const ownershipRow = Array.from(host.querySelectorAll("span")).find(
      (span) => span.textContent === "_railway-verify.mcp.example.com",
    )!.parentElement!;
    const routingRow = Array.from(host.querySelectorAll("span")).find(
      (span) => span.textContent === "gateway.up.railway.app",
    )!.parentElement!.parentElement!;
    expect(ownershipRow.textContent).toContain("Propagated");
    expect(routingRow.textContent).toContain("Needs DNS update");
    expect(routingRow.textContent).not.toContain("Propagated");
    expect(host.textContent).toContain("Project domain verification: verified");
  });

  it("renders the non-conflicting project verification record once with generic aliases", async () => {
    vi.mocked(fetchCustomDomain).mockResolvedValue({
      ...initialStatus,
      verified: false,
      verification_token: "project-token",
      verification_record_name: "_mcp-verify.mcp.example.com",
      ownership_verification_record_name: "_mcp-verify.mcp.example.com",
      ownership_verification_record_value: "project-token",
    });
    await renderSection();
    expect(host.textContent).toContain("Project verification record");
    expect(host.textContent?.match(/project-token/g)).toHaveLength(1);
    expect(host.textContent).toContain("_mcp-verify.mcp.example.com");
    expect(host.textContent).toContain("_railway-verify.mcp.example.com");
  });

  it("copies complete Railway records, retaining both verification and routing", async () => {
    await renderSection();
    await click("Copy Railway records");
    expect(copyTextToClipboard).toHaveBeenCalledWith(
      "_railway-verify.mcp.example.com\tTXT\trailway-token\nmcp.example.com\tCNAME\tgateway.up.railway.app",
      { success: "Railway DNS records copied to clipboard", error: "Could not copy DNS records" },
    );
    expect(button("Copy Railway records").disabled).toBe(false);
  });

  it("shows refresh progress and prevents hostname changes during verification", async () => {
    const check = deferred<CustomDomainStatus>();
    vi.mocked(verifyProjectCustomDomain).mockReturnValue(check.promise);
    await renderSection();
    await enterHostname("next.example.com");
    await click("Refresh DNS/TLS");
    await waitFor(() => { expect(host.textContent).toContain("Checking DNS and TLS"); });
    expect(host.textContent).toContain("Railway TLS certificate: requesting status");
    expect(button("Update Hostname").disabled).toBe(true);
    expect(host.querySelector("input")!.disabled).toBe(true);
    await act(async () => { check.resolve(issuedStatus); await check.promise; });
    await waitFor(() => { expect(host.textContent).toContain("TLS issued"); });
  });

  it("renders successive TLS refreshes and later query refetches", async () => {
    await renderSection();
    await click("Refresh DNS/TLS");
    await waitFor(() => { expect(host.textContent).toContain("TLS issued"); });
    vi.mocked(verifyProjectCustomDomain).mockResolvedValue(initialStatus);
    await click("Refresh DNS/TLS");
    await waitFor(() => { expect(host.textContent).toContain("TLS pending"); });
    vi.mocked(fetchCustomDomain).mockResolvedValue(issuedStatus);
    await act(async () => {
      await queryClient.refetchQueries({ queryKey: ["custom-domain", "project-1"] });
    });
    await waitFor(() => { expect(host.textContent).toContain("TLS issued"); });
  });

  it("displays the new hostname after verification then replacement and blocks overlapping refresh", async () => {
    const save = deferred<CustomDomainStatus>();
    vi.mocked(setProjectCustomDomain).mockReturnValue(save.promise);
    await renderSection();
    await click("Refresh DNS/TLS");
    await waitFor(() => { expect(host.textContent).toContain("TLS issued"); });
    await enterHostname("next.example.com");
    await click("Update Hostname");
    await waitFor(() => { expect(button("Refresh DNS/TLS").disabled).toBe(true); });
    expect(setProjectCustomDomain).toHaveBeenCalledWith("project-1", "next.example.com");
    await act(async () => {
      save.resolve({
        hostname: "next.example.com",
        verified: false,
        verification_token: "new-token",
        certificate_status: "pending",
        platform_dns_records: [],
      });
      await save.promise;
    });
    await waitFor(() => {
      expect(host.textContent).toContain("Hostname: next.example.com");
      expect(host.textContent).toContain("new-token");
      expect(host.textContent).not.toContain("mcp.example.com");
      expect(host.textContent).not.toContain("TLS issued");
    });
  });

  it("does not let an earlier in-flight query overwrite a verification result", async () => {
    await renderSection();
    const staleRead = deferred<CustomDomainStatus>();
    vi.mocked(fetchCustomDomain).mockReturnValue(staleRead.promise);
    let refetch: Promise<void>;
    await act(async () => {
      refetch = queryClient.refetchQueries({ queryKey: ["custom-domain", "project-1"] });
    });
    await click("Refresh DNS/TLS");
    await waitFor(() => { expect(host.textContent).toContain("TLS issued"); });
    await act(async () => {
      staleRead.resolve(initialStatus);
      await staleRead.promise;
      await refetch;
    });
    expect(host.textContent).toContain("TLS issued");
    expect(queryClient.getQueryData(["custom-domain", "project-1"])).toEqual(issuedStatus);
  });

  it("preserves extra validation record types and does not claim unknown status is propagated", async () => {
    vi.mocked(fetchCustomDomain).mockResolvedValue({
      ...initialStatus,
      platform_dns_records: [{ type: "CAA", name: "example.com", value: '0 issue "letsencrypt.org"', status: "NEW_STATUS" }],
    });
    await renderSection();
    expect(host.textContent).toContain("CAA");
    expect(host.textContent).toContain('0 issue "letsencrypt.org"');
    expect(host.textContent).toContain("Not confirmed");
  });

  it("refreshes Railway records when verification returns missing DNS requirements", async () => {
    await renderSection();
    vi.mocked(fetchCustomDomain).mockResolvedValue({
      ...initialStatus,
      platform_dns_records: [{ type: "TXT", name: "_railway-verify.mcp.example.com", value: "new-railway-token" }],
    });
    vi.mocked(verifyProjectCustomDomain).mockRejectedValue(new ApiError("Bad Request", 400, {
      reason: "Railway is still waiting for required DNS records.",
    }));
    await click("Refresh DNS/TLS");
    await waitFor(() => {
      expect(host.textContent).toContain("new-railway-token");
      expect(host.textContent).toContain("Railway is still waiting for required DNS records.");
    });
    expect(host.textContent).not.toContain("gateway.up.railway.app");
    expect(button("Refresh DNS/TLS").disabled).toBe(false);
  });

  it("shows missing Railway provisioning configuration without claiming TLS is ready", async () => {
    vi.mocked(fetchCustomDomain).mockResolvedValue({
      ...initialStatus,
      platform_dns_records: [],
      certificate_status: "not_configured",
      certificate_message: "Railway domain provisioning is not configured. Set a Railway project token on the Gateway service.",
    });
    await renderSection();
    expect(host.textContent).toContain("TLS not configured");
    expect(host.textContent).toContain("Set a Railway project token on the Gateway service.");
    expect(host.textContent).not.toContain("TLS issued");
    expect(button("Refresh DNS/TLS").disabled).toBe(false);
  });

  it("shows save failures and does not repeat the certificate message in instructions", async () => {
    vi.mocked(fetchCustomDomain).mockResolvedValue({
      ...initialStatus,
      instructions: `${initialStatus.certificate_message}\nAdd the required CNAME record.`,
    });
    vi.mocked(setProjectCustomDomain).mockRejectedValue(new Error("Unavailable"));
    await renderSection();
    expect(host.textContent?.match(/Railway TLS certificate provisioning is pending\./g)).toHaveLength(1);
    expect(host.textContent).toContain("Add the required CNAME record.");
    await enterHostname("next.example.com");
    await click("Update Hostname");
    await waitFor(() => { expect(host.textContent).toContain("Could not save the custom hostname."); });
  });
});
