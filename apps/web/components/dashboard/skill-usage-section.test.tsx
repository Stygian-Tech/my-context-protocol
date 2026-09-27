/** @vitest-environment jsdom */
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { act } from "react";
import { createRoot, type Root } from "react-dom/client";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { SkillUsageSection } from "./skill-usage-section";
import { SkillRuntimeSection } from "./skill-runtime-section";
import { fetchProjectSkillRuntime, fetchProjectSkillUsage, updateProjectSkillRuntime } from "@/lib/projects-api";
import type { ProjectSkillUsage, SkillUsageCounts, SkillUsageRow } from "@/lib/types";
vi.mock("@/lib/projects-api", () => ({ fetchProjectSkillRuntime: vi.fn(), fetchProjectSkillUsage: vi.fn(), updateProjectSkillRuntime: vi.fn() }));
const counts: SkillUsageCounts = { surfaced: 6, instructions_delivered: 2, supporting_file_read: 3, resolver_selected: 1, resolver_suggested: 2, resolver_excluded: 3, agent_reported_used: 1, agent_reported_skipped: 0, legacy_resolver_selected: 4 };
const skill: SkillUsageRow = { skill_id: "test-skill", name: "A Long Skill Name ".repeat(12), is_current: true, last_activity: "2026-09-27T00:00:00Z", counts, versions: [], resolver_exclusion_reasons: [], agent_skip_reasons: [] };
const initial: ProjectSkillUsage = { collection_enabled: true, retention_days: 30, requested_window: "7d", effective_from: "2026-09-20T00:00:00Z", effective_to: "2026-09-27T00:00:00Z", reporting_coverage: "partial", historical_measurements: "legacy_resolver_only", page: 1, page_size: 25, total: 1, skills: [skill] };
async function waitFor(check: () => void) {
  let error: unknown;
  for (let i = 0; i < 100; i++) { try { check(); return; } catch (caught) { error = caught; await act(async () => { await new Promise((resolve) => setTimeout(resolve, 10)); }); } }
  throw error;
}

describe("SkillUsageSection", () => {
  let host: HTMLDivElement; let root: Root; let client: QueryClient;
  beforeEach(() => {
    client = new QueryClient({ defaultOptions: { queries: { retry: false }, mutations: { retry: false } } });
    host = document.createElement("div"); document.body.appendChild(host); root = createRoot(host);
    vi.mocked(fetchProjectSkillUsage).mockResolvedValue(initial);
    vi.mocked(fetchProjectSkillRuntime).mockResolvedValue({ telemetry_enabled: false, telemetry_retention_days: 14, semantic_enabled: false, feedback_issue_creation_enabled: false, assignments: [], recent_events: [] });
  });
  afterEach(async () => { await act(async () => root.unmount()); client.clear(); host.remove(); vi.resetAllMocks(); });
  async function render(withSettings = false) {
    await act(async () => { root.render(<QueryClientProvider client={client}><SkillUsageSection projectId="p" />{withSettings ? <SkillRuntimeSection projectId="p" /> : null}</QueryClientProvider>); });
  }
  async function loaded() { await waitFor(() => expect(host.textContent).toContain("Effective window:")); }
  async function click(text: string) {
    const button = [...host.querySelectorAll("button")].find((item) => item.textContent?.includes(text));
    expect(button).toBeDefined(); await act(async () => button!.click());
  }
  async function changeWindow(value: string) {
    await act(async () => { const select = host.querySelector<HTMLSelectElement>('[aria-label="Skill usage time window"]')!; select.value = value; select.dispatchEvent(new Event("change", { bubbles: true })); });
  }
  it("distinguishes observed and reported activity without inferring missing skips", async () => {
    await render(); await loaded();
    expect(fetchProjectSkillUsage).toHaveBeenCalledWith("p", { window: "7d", page: 1, page_size: 25, sort: "activity", direction: "desc" });
    expect(host.textContent).toContain("Agent-Reported Used"); expect(host.textContent).toContain("Agent-Reported Skipped");
    expect(host.textContent).toContain("a missing report is unknown, never a skipped skill");
    expect(host.textContent).toContain("Historical measurements before this feature are unavailable");
    expect(host.textContent).toContain("1 skill · Page 1 of 1");
    expect(host.querySelector('[aria-expanded="false"]')?.textContent).toContain(skill.name);
    const cells = host.querySelectorAll("tbody tr td"); expect(cells[7].textContent).toBe("0");
  });
  it("shows disabled collection with retained history and zero-activity current skills", async () => {
    vi.mocked(fetchProjectSkillUsage).mockResolvedValue({ ...initial, collection_enabled: false, skills: [{ ...skill, last_activity: null, counts: Object.fromEntries(Object.keys(counts).map((key) => [key, 0])) as unknown as SkillUsageCounts }] });
    await render(); await loaded(); expect(host.textContent).toContain("retained history remains visible"); expect(host.textContent).toContain("No recorded activity"); expect(host.querySelectorAll("tbody tr")).toHaveLength(1);
  });
  it("marks legacy-only measurements unavailable instead of inventing zero usage", async () => {
    const legacyCounts = { ...Object.fromEntries(Object.keys(counts).map((key) => [key, 0])), legacy_resolver_selected: 4 } as unknown as SkillUsageCounts;
    vi.mocked(fetchProjectSkillUsage).mockResolvedValue({ ...initial, skills: [{ ...skill, counts: legacyCounts, versions: [{ release_id: null, version: null, checksum: null, counts: legacyCounts }] }] });
    await render(); await loaded(); expect(host.textContent).toContain("Legacy Measurements Only");
    expect(host.querySelectorAll('[aria-label="Unavailable for legacy activity"]')).toHaveLength(7);
    await click(skill.name.trim()); await waitFor(() => expect(host.textContent).toContain("Unknown (legacy)"));
    expect(host.querySelectorAll('[aria-label="Unavailable for legacy activity"]')).toHaveLength(15);
  });
  it("loads expansion through the exact skill filter and separates legacy versions and reasons", async () => {
    vi.mocked(fetchProjectSkillUsage).mockImplementation(async (_project, params) => params?.skill_id ? { ...initial, skills: [{ ...skill, is_current: false, versions: [{ release_id: null, version: null, checksum: null, counts }], agent_skip_reasons: [{ reason: "not_relevant", count: 2 }], resolver_exclusion_reasons: [{ reason: "missing_capability", count: 3 }] }] } : initial);
    await render(); await loaded(); await click(skill.name.trim());
    await waitFor(() => expect(host.textContent).toContain("Unknown (legacy)"));
    expect(fetchProjectSkillUsage).toHaveBeenCalledWith("p", { window: "7d", skill_id: "test-skill" });
    expect(host.textContent).toContain("Supporting File Reads: 3"); expect(host.textContent).toContain("Legacy Resolver Selections: 4"); expect(host.textContent).toContain("Not Relevant"); expect(host.textContent).toContain("Private deliberation is not observable");
    expect(host.querySelector('[aria-expanded="true"]')).not.toBeNull();
    await click(skill.name.trim()); expect(host.textContent).not.toContain("Versions and Releases");
  });
  it("changes server sorting, pagination and window while resetting page", async () => {
    vi.mocked(fetchProjectSkillUsage).mockImplementation(async (_p, params) => ({ ...initial, total: 26, page: params?.page ?? 1 }));
    await render(); await loaded(); await click("Next"); await waitFor(() => expect(host.textContent).toContain("Page 2 of 2"));
    await click("Surfaced"); await waitFor(() => expect(fetchProjectSkillUsage).toHaveBeenLastCalledWith("p", expect.objectContaining({ page: 1, sort: "surfaced", direction: "desc" })));
    await loaded(); await click("Surfaced"); await waitFor(() => expect(host.querySelector('[aria-sort="ascending"]')?.textContent).toContain("Surfaced"));
    await changeWindow("24h"); await waitFor(() => expect(fetchProjectSkillUsage).toHaveBeenLastCalledWith("p", expect.objectContaining({ window: "24h", page: 1 })));
    await changeWindow("30d"); await waitFor(() => expect(fetchProjectSkillUsage).toHaveBeenLastCalledWith("p", expect.objectContaining({ window: "30d", page: 1 })));
  });
  it("does not refetch runtime settings or discard unsaved changes while filtering", async () => {
    await render(true); await loaded(); await waitFor(() => expect(host.textContent).toContain("Save Runtime"));
    const checkbox = host.querySelector<HTMLInputElement>("#runtime-skill-telemetry")!;
    await act(async () => checkbox.click()); expect(checkbox.checked).toBe(true);
    await changeWindow("24h"); await loaded(); expect(checkbox.checked).toBe(true); expect(fetchProjectSkillRuntime).toHaveBeenCalledTimes(1);
    vi.mocked(updateProjectSkillRuntime).mockResolvedValue({ telemetry_enabled: true, telemetry_retention_days: 14, semantic_enabled: false, feedback_issue_creation_enabled: false, assignments: [], recent_events: [] });
    await click("Save Runtime"); await waitFor(() => expect(updateProjectSkillRuntime).toHaveBeenCalledWith("p", expect.objectContaining({ telemetry_enabled: true, telemetry_retention_days: 14 })));
  });
  it("shows loading, an actionable error and a distinct empty state", async () => {
    let reject: (reason?: unknown) => void = () => {};
    vi.mocked(fetchProjectSkillUsage).mockReturnValueOnce(new Promise((_resolve, rejectPromise) => { reject = rejectPromise; }));
    await render(); expect(host.querySelector('[aria-label="Loading skill usage"]')).not.toBeNull();
    await act(async () => reject(new Error("Unavailable"))); await waitFor(() => expect(host.textContent).toContain("Could not load skill usage."));
    vi.mocked(fetchProjectSkillUsage).mockResolvedValue({ ...initial, total: 0, skills: [] });
    await click("Retry"); await loaded(); expect(host.textContent).toContain("No current skills or retained skill activity");
  });
  it("keeps failed detail queries isolated from the table", async () => {
    vi.mocked(fetchProjectSkillUsage).mockImplementation(async (_p, params) => { if (params?.skill_id) throw new Error("Details unavailable"); return initial; });
    await render(); await loaded(); await click(skill.name.trim()); await waitFor(() => expect(host.textContent).toContain("Could not load skill details."));
    expect(host.querySelector("table")).not.toBeNull(); expect(host.textContent).toContain("Retry Details");
  });
});
