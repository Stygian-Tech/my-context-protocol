/** @vitest-environment jsdom */
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { act, type ReactNode } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { RepoConnectionSection } from "./repo-connection-section";
import { connectRepo, fetchRepoConnection, fetchUserGithubRepos } from "@/lib/projects-api";
import { ApiError } from "@/lib/api";
import { assertGitHubInstallUrl } from "@/lib/trusted-redirect";
vi.mock("@/lib/projects-api", () => ({ fetchRepoConnection: vi.fn(), fetchUserGithubRepos: vi.fn(), connectRepo: vi.fn(), triggerSync: vi.fn() }));
vi.mock("@/lib/trusted-redirect", () => ({ assertGitHubInstallUrl: vi.fn() }));
// Exercise the connection flow independently of popup positioning.
vi.mock("@/components/ui/select", () => ({
  Select: ({ value, onValueChange, children }: { value: string; onValueChange: (value: string) => void; children: ReactNode }) => <select aria-label="Repository" value={value ?? ""} onChange={(event) => onValueChange(event.target.value)}><option value="">Choose a repository…</option>{children}</select>,
  SelectTrigger: () => null, SelectValue: () => null,
  SelectContent: ({ children }: { children: ReactNode }) => children,
  SelectItem: ({ value }: { value: string }) => <option value={value}>{value}</option>,
}));
const repo = { full_name: "owner/skills", owner_login: "owner", name: "skills", default_branch: "main", is_private: true };
async function waitFor(assertion: () => void) {
  let error: unknown;
  for (let attempt = 0; attempt < 100; attempt++) {
    try { assertion(); return; } catch (caught) { error = caught; }
    await act(async () => { await new Promise((resolve) => setTimeout(resolve, 10)); });
  }
  throw error;
}
describe("RepoConnectionSection GitHub access", () => {
  let host: HTMLDivElement; let root: Root; let client: QueryClient;
  beforeEach(() => {
    window.history.replaceState({}, "", "/projects/project-1"); sessionStorage.clear();
    vi.mocked(fetchRepoConnection).mockResolvedValue(null); vi.mocked(fetchUserGithubRepos).mockResolvedValue([]);
    client = new QueryClient({ defaultOptions: { queries: { retry: false }, mutations: { retry: false } } });
    host = document.createElement("div"); document.body.appendChild(host); root = createRoot(host);
  });
  afterEach(async () => { await act(async () => root.unmount()); host.remove(); client.clear(); vi.resetAllMocks(); vi.restoreAllMocks(); sessionStorage.clear(); });
  async function render() {
    await act(async () => root.render(<QueryClientProvider client={client}><RepoConnectionSection projectId="project-1" /></QueryClientProvider>));
    await waitFor(() => expect(host.textContent).not.toBe(""));
  }
  async function click(label: string) {
    const button = [...host.querySelectorAll("button")].find((item) => item.textContent === label);
    expect(button).toBeDefined(); await act(async () => button!.click());
  }
  async function open() {
    await render(); await waitFor(() => expect(host.textContent).toContain("Connect Repository")); await click("Connect Repository");
    await waitFor(() => expect(host.querySelector("a")).not.toBeNull());
  }
  it("offers project-scoped installation and refresh for an empty accessible list", async () => {
    await open(); await waitFor(() => expect(host.textContent).toContain("No repositories are accessible to MyContextProtocol yet."));
    expect(host.textContent).not.toContain("No repositories found for this account");
    expect(host.querySelector("a")?.getAttribute("href")).toBe("/api/auth/github/app/install?project_id=project-1");
    vi.mocked(fetchUserGithubRepos).mockResolvedValue([repo]); await click("Refresh Repositories");
    await waitFor(() => expect(host.querySelector("select")?.textContent).toContain(repo.full_name)); expect(fetchUserGithubRepos).toHaveBeenCalledTimes(2);
  });
  it("reopens after installation without a selection and invalidates a fresh cached empty list", async () => {
    client.setQueryData(["github-repos"], []); vi.mocked(fetchUserGithubRepos).mockResolvedValue([repo]);
    window.history.replaceState({}, "", "/projects/project-1?github_app_installed=1&tab=repository#details"); await render();
    await waitFor(() => expect(host.querySelector("select")?.textContent).toContain(repo.full_name));
    expect(fetchUserGithubRepos).toHaveBeenCalledTimes(1); expect(window.location.search).toBe("?tab=repository"); expect(window.location.hash).toBe("#details");
  });
  it("restores a pending selection and consumes its session state", async () => {
    sessionStorage.setItem("pendingRepoConnect:project-1", JSON.stringify({ full_name: repo.full_name, branch: "main" }));
    vi.mocked(fetchUserGithubRepos).mockResolvedValue([repo]); window.history.replaceState({}, "", "/projects/project-1?github_app_installed=1&resume_owner=owner&resume_repo=skills"); await render();
    await waitFor(() => expect(host.querySelector("select")?.value).toBe(repo.full_name));
    expect(sessionStorage.getItem("pendingRepoConnect:project-1")).toBeNull(); expect(window.location.search).toBe("");
  });
  it("reopens and refreshes after malformed pending selection", async () => {
    sessionStorage.setItem("pendingRepoConnect:project-1", "broken-json"); window.history.replaceState({}, "", "/projects/project-1?github_app_installed=1"); await render();
    await waitFor(() => expect(host.textContent).toContain("No repositories are accessible")); expect(sessionStorage.getItem("pendingRepoConnect:project-1")).toBeNull();
  });
  it("resumes query-provided selection without pending session data", async () => {
    vi.mocked(fetchUserGithubRepos).mockResolvedValue([repo]); window.history.replaceState({}, "", "/projects/project-1?github_app_installed=1&resume_owner=owner&resume_repo=skills"); await render();
    await waitFor(() => expect(host.querySelector("select")?.value).toBe(repo.full_name)); expect(window.location.search).toBe("");
  });
  it("keeps access configuration available on lookup errors and retries", async () => {
    vi.mocked(fetchUserGithubRepos).mockRejectedValue(new ApiError("Unavailable", 502)); await open();
    await waitFor(() => expect(host.textContent).toContain("GitHub did not return your repository list")); expect(host.querySelector("a")?.textContent).toBe("Configure GitHub Access");
    vi.mocked(fetchUserGithubRepos).mockResolvedValue([repo]); await click("Retry"); await waitFor(() => expect(host.querySelector("select")?.textContent).toContain(repo.full_name));
  });
  it("preserves connect 409 installation resume", async () => {
    // jsdom reports attempted external navigation, which this test verifies through the URL guard.
    const navigationError = vi.spyOn(console, "error").mockImplementation(() => {});
    vi.mocked(fetchUserGithubRepos).mockResolvedValue([repo]); vi.mocked(connectRepo).mockRejectedValue(new ApiError("Install required", 409, { install_url: "https://github.com/apps/test/installations/new" })); await open();
    await waitFor(() => expect(host.querySelector("select")).not.toBeNull());
    const select = host.querySelector("select")!;
    await act(async () => { select.value = repo.full_name; select.dispatchEvent(new Event("change", { bubbles: true })); }); await click("Connect");
    await waitFor(() => expect(assertGitHubInstallUrl).toHaveBeenCalledWith("https://github.com/apps/test/installations/new"));
    expect(connectRepo).toHaveBeenCalledWith("project-1", { owner: "owner", repo: "skills", branch: "main" });
    expect(JSON.parse(sessionStorage.getItem("pendingRepoConnect:project-1")!)).toMatchObject({ full_name: repo.full_name, branch: "main" });
    expect(navigationError).toHaveBeenCalledTimes(1);
    expect(String(navigationError.mock.calls[0][0])).toContain("Not implemented: navigation");
    navigationError.mockRestore();
  });
});
