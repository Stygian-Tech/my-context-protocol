/** @vitest-environment jsdom */
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { act } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { ApiError } from "@/lib/api";
import { activateRelease, fetchCompiledSkills, fetchReleases } from "@/lib/projects-api";
import type { CompiledSkill, Release } from "@/lib/types";
import { ReleaseTable } from "./release-table";

const navigation = vi.hoisted(() => ({ replace: vi.fn() }));

vi.mock("@/lib/projects-api", () => ({
  activateRelease: vi.fn(), fetchReleases: vi.fn(), fetchCompiledSkills: vi.fn(),
}));
vi.mock("next/navigation", () => ({
  usePathname: () => "/projects/project-1",
  useRouter: () => navigation,
  useSearchParams: () => new URLSearchParams(),
}));
vi.mock("./release-skill-metadata-dialog", () => ({
  ReleaseSkillMetadataDialog: ({ open, releaseId, initialMcpFocus }: {
    open: boolean; releaseId: string | null; initialMcpFocus: { skillId: string; field: string } | null;
  }) => open ? <div data-testid="metadata-dialog">{releaseId}:{initialMcpFocus?.skillId}:{initialMcpFocus?.field}</div> : null,
}));
vi.mock("./release-validation-dialog", () => ({ ReleaseValidationDialog: () => null }));
vi.mock("./release-body-changes-dialog", () => ({ ReleaseBodyChangesDialog: () => null }));

function release(id: string, projectId = "project-1"): Release {
  return { id, project_id: projectId, commit_sha: `${id}-commit`, status: "ready", created_at: "2026-09-29T12:00:00Z", is_active: false };
}
async function waitFor(assertion: () => void) {
  let error: unknown;
  for (let attempt = 0; attempt < 100; attempt++) {
    try { assertion(); return; } catch (caught) { error = caught; }
    await act(async () => { await new Promise((resolve) => setTimeout(resolve, 10)); });
  }
  throw error;
}
function deferred() {
  let resolve!: () => void;
  let reject!: (reason: unknown) => void;
  const promise = new Promise<void>((done, fail) => { resolve = done; reject = fail; });
  return { promise, resolve, reject };
}

describe("ReleaseTable activation feedback", () => {
  let host: HTMLDivElement;
  let root: Root;
  let client: QueryClient;
  beforeEach(() => {
    sessionStorage.clear();
    vi.mocked(fetchReleases).mockResolvedValue([release("release-1"), release("release-2")]);
    vi.mocked(fetchCompiledSkills).mockResolvedValue([]);
    client = new QueryClient({ defaultOptions: { queries: { retry: false }, mutations: { retry: false } } });
    host = document.createElement("div");
    document.body.appendChild(host);
    root = createRoot(host);
  });
  afterEach(async () => {
    await act(async () => root.unmount());
    client.clear(); host.remove(); sessionStorage.clear(); vi.resetAllMocks();
  });
  async function render(projectId = "project-1") {
    await act(async () => root.render(<QueryClientProvider client={client}><ReleaseTable projectId={projectId}/></QueryClientProvider>));
    await waitFor(() => expect(host.querySelectorAll("tbody tr")).toHaveLength(2));
  }
  function row(index: number) { return host.querySelectorAll<HTMLTableRowElement>("tbody tr")[index]; }
  async function click(index: number, label = "Activate") {
    const button = [...row(index).querySelectorAll("button")].find((item) => item.textContent === label);
    expect(button).toBeDefined();
    await act(async () => button!.click());
  }

  it("shows the backend readiness reason and opens the affected release metadata for review", async () => {
    vi.mocked(activateRelease).mockRejectedValue(new ApiError("Bad Request", 400, { reason: "All compiled skills must be ready before activation" }));
    vi.mocked(fetchCompiledSkills).mockResolvedValue([{ id: "blocked-skill", status: "not_publishable", summary: "" } as CompiledSkill]);
    await render(); await click(0);
    await waitFor(() => expect(row(0).querySelector('[role="alert"]')?.textContent).toContain("All compiled skills must be ready before activation"));
    expect(row(1).querySelector('[role="alert"]')).toBeNull();
    await click(0, "Review MCP Metadata");
    await waitFor(() => expect(host.querySelector('[data-testid="metadata-dialog"]')?.textContent).toBe("release-1:blocked-skill:summary"));
    expect(fetchCompiledSkills).toHaveBeenCalledWith("project-1", "release-1");
  });

  it("clears the failed row while a retry is pending and refetches the active badge after success", async () => {
    const retry = deferred();
    vi.mocked(activateRelease).mockRejectedValueOnce(new ApiError("Conflict", 409, { reason: "Release is not ready" })).mockReturnValueOnce(retry.promise);
    await render(); await click(0);
    await waitFor(() => expect(row(0).querySelector('[role="alert"]')).not.toBeNull());
    await click(0);
    await waitFor(() => {
      expect(row(0).querySelector('[role="alert"]')).toBeNull();
      expect(row(0).querySelector<HTMLButtonElement>("button")?.disabled).toBe(true);
    });
    vi.mocked(fetchReleases).mockResolvedValue([{ ...release("release-1"), is_active: true }, release("release-2")]);
    await act(async () => retry.resolve());
    await waitFor(() => expect(row(0).textContent).toContain("Active"));
    expect([...row(0).querySelectorAll("button")].some((button) => button.textContent === "Activate")).toBe(false);
    expect(row(0).querySelector('[role="alert"]')).toBeNull();
  });

  it("invalidates every existing project and account cache after activation", async () => {
    const keys = [
      ["project-catalog", "project-1"], ["project", "project-1"],
      ["project-dashboard-summary", "project-1"], ["account-dashboard-summary"],
    ];
    keys.forEach((key) => client.setQueryData(key, { retained: true }));
    client.setQueryData(["project", "another-project"], { retained: true });
    vi.mocked(activateRelease).mockResolvedValue(undefined);
    await render(); await click(0);
    await waitFor(() => keys.forEach((key) => expect(client.getQueryState(key)?.isInvalidated).toBe(true)));
    expect(fetchReleases).toHaveBeenCalledTimes(2);
    expect(client.getQueryState(["project", "another-project"])?.isInvalidated).toBe(false);
  });

  it.each([
    { unknown: "failure" },
    new Error("Network connection lost"),
    new ApiError("HTTP error", 502),
  ])("uses a readable fallback for unknown failures without offering an unrelated readiness action: %s", async (failure) => {
    vi.mocked(activateRelease).mockRejectedValue(failure);
    await render(); await click(0);
    await waitFor(() => expect(row(0).querySelector('[role="alert"]')?.textContent).toContain("Could not activate this release. Try again."));
    expect(row(0).textContent).not.toContain("[object Object]");
    expect(row(0).textContent).not.toContain("Review MCP Metadata");
  });

  it("keeps failures scoped to their release and clears only the retried row", async () => {
    const retry = deferred();
    vi.mocked(activateRelease).mockRejectedValueOnce(new ApiError("Server error", 500, { reason: "First failure" })).mockRejectedValueOnce(new ApiError("Server error", 500, { reason: "Second failure" })).mockReturnValueOnce(retry.promise);
    await render(); await click(0);
    await waitFor(() => expect(row(0).querySelector('[role="alert"]')?.textContent).toContain("First failure"));
    await click(1);
    await waitFor(() => expect(row(1).querySelector('[role="alert"]')?.textContent).toContain("Second failure"));
    expect(row(0).querySelector('[role="alert"]')?.textContent).toContain("First failure");
    await click(0);
    await waitFor(() => expect(row(0).querySelector('[role="alert"]')).toBeNull());
    expect(row(1).querySelector('[role="alert"]')?.textContent).toContain("Second failure");
    await act(async () => retry.resolve());
  });

  it("isolates a late failed activation from a newly selected project", async () => {
    const activation = deferred();
    vi.mocked(activateRelease).mockReturnValue(activation.promise);
    await render(); await click(0);
    vi.mocked(fetchReleases).mockResolvedValue([release("release-1", "project-2"), release("release-2", "project-2")]);
    await render("project-2");
    await act(async () => activation.reject(new ApiError("Old project failure", 500)));
    await waitFor(() => expect(client.isMutating()).toBe(0));
    expect(host.querySelector('[role="alert"]')).toBeNull();
    expect(host.textContent).not.toContain("Old project failure");
    expect([...row(0).querySelectorAll("button")].find((button) => button.textContent === "Activate")?.disabled).toBe(false);
  });

  it("does not navigate or reopen old metadata when a lookup finishes after changing projects", async () => {
    let resolveSkills!: (skills: CompiledSkill[]) => void;
    const pendingSkills = new Promise<CompiledSkill[]>((resolve) => { resolveSkills = resolve; });
    vi.mocked(fetchCompiledSkills).mockReturnValueOnce(pendingSkills);
    vi.mocked(activateRelease).mockRejectedValue(new ApiError("Bad Request", 400, { reason: "All compiled skills must be ready before activation" }));
    await render(); await click(0);
    await waitFor(() => expect(row(0).textContent).toContain("Review MCP Metadata"));
    await click(0, "Review MCP Metadata");
    expect(fetchCompiledSkills).toHaveBeenCalledWith("project-1", "release-1");
    vi.mocked(fetchReleases).mockResolvedValue([release("release-1", "project-2"), release("release-2", "project-2")]);
    await render("project-2");
    await act(async () => resolveSkills([{ id: "old-blocked-skill", status: "not_publishable", summary: "" } as CompiledSkill]));
    await waitFor(() => expect(client.isFetching({ queryKey: ["compiled-skills", "project-1", "release-1"] })).toBe(0));
    expect(navigation.replace).not.toHaveBeenCalled();
    expect(sessionStorage.getItem("mcp-deep-link-from-ui")).toBeNull();
    expect(host.querySelector('[data-testid="metadata-dialog"]')).toBeNull();
  });
});
