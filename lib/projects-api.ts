import { api } from "./api";
import type {
  Project,
  RepoConnection,
  Release,
  ApiKey,
  RequestLog,
  GithubRepoListItem,
  ProjectCatalog,
  ReleaseValidationReport,
  CompiledSkill,
  AccountDashboardSummary,
  ProjectDashboardSummary,
} from "./types";
import type {
  AccountDashboardTimeseries,
  DashboardTimeseriesRange,
  ProjectDashboardTimeseries,
} from "./dashboard-timeseries";

export async function fetchProjects(): Promise<Project[]> {
  const response = await api.get<Project[] | { projects: Project[] }>("/projects");
  if (Array.isArray(response)) return response;
  return response.projects ?? [];
}

export async function fetchProject(id: string): Promise<Project> {
  return api.get<Project>(`/projects/${id}`);
}

export async function fetchAccountDashboardSummary(): Promise<AccountDashboardSummary> {
  return api.get<AccountDashboardSummary>("/dashboard/summary");
}

export async function fetchProjectDashboardSummary(
  projectId: string
): Promise<ProjectDashboardSummary> {
  return api.get<ProjectDashboardSummary>(
    `/projects/${projectId}/dashboard/summary`
  );
}

export async function fetchAccountDashboardTimeseries(
  range: DashboardTimeseriesRange = "24h"
): Promise<AccountDashboardTimeseries> {
  const q = encodeURIComponent(range);
  return api.get<AccountDashboardTimeseries>(`/dashboard/timeseries?range=${q}`);
}

export async function fetchProjectDashboardTimeseries(
  projectId: string,
  range: DashboardTimeseriesRange = "24h"
): Promise<ProjectDashboardTimeseries> {
  const q = encodeURIComponent(range);
  return api.get<ProjectDashboardTimeseries>(
    `/projects/${projectId}/dashboard/timeseries?range=${q}`
  );
}

export async function fetchProjectCatalog(projectId: string): Promise<ProjectCatalog> {
  return api.get<ProjectCatalog>(`/projects/${projectId}/catalog`);
}

export async function createProject(data: {
  name: string;
  slug: string;
}): Promise<Project> {
  return api.post<Project>("/projects", data);
}

export async function updateProject(
  projectId: string,
  body: { name: string }
): Promise<Project> {
  return api.patch<Project>(`/projects/${projectId}`, body);
}

export interface CustomDomainStatus {
  hostname: string | null;
  verified: boolean;
  verification_token?: string | null;
  instructions?: string | null;
}

export async function fetchCustomDomain(projectId: string): Promise<CustomDomainStatus> {
  return api.get<CustomDomainStatus>(`/projects/${projectId}/custom-domain`);
}

export async function setProjectCustomDomain(
  projectId: string,
  hostname: string
): Promise<CustomDomainStatus> {
  return api.post<CustomDomainStatus>(`/projects/${projectId}/custom-domain`, { hostname });
}

export async function verifyProjectCustomDomain(projectId: string): Promise<CustomDomainStatus> {
  return api.post<CustomDomainStatus>(`/projects/${projectId}/custom-domain/verify`);
}

export async function fetchRepoConnection(projectId: string): Promise<RepoConnection | null> {
  try {
    return await api.get<RepoConnection>(`/projects/${projectId}/repo-connection`);
  } catch {
    return null;
  }
}

export async function fetchUserGithubRepos(): Promise<GithubRepoListItem[]> {
  return api.get<GithubRepoListItem[]>("/github/repos");
}

export async function connectRepo(
  projectId: string,
  data: { owner: string; repo: string; branch: string }
): Promise<RepoConnection> {
  return api.post<RepoConnection>(`/projects/${projectId}/connect-repo`, data);
}

export async function triggerSync(projectId: string): Promise<void> {
  await api.post(`/projects/${projectId}/sync`);
}

export async function fetchReleases(projectId: string): Promise<Release[]> {
  const response = await api.get<Release[] | { releases: Release[] }>(
    `/projects/${projectId}/releases`
  );
  if (Array.isArray(response)) return response;
  return response.releases ?? [];
}

export async function activateRelease(
  projectId: string,
  releaseId: string
): Promise<void> {
  await api.post(`/projects/${projectId}/releases/${releaseId}/activate`);
}

export async function fetchReleaseValidation(
  projectId: string,
  releaseId: string
): Promise<ReleaseValidationReport> {
  const r = await api.get<ReleaseValidationReport>(
    `/projects/${projectId}/releases/${releaseId}/validation`
  );
  return {
    ...r,
    errors: r.errors ?? [],
    warnings: r.warnings ?? [],
  };
}

export async function fetchCompiledSkills(
  projectId: string,
  releaseId: string
): Promise<CompiledSkill[]> {
  return api.get<CompiledSkill[]>(
    `/projects/${projectId}/releases/${releaseId}/compiled-skills`
  );
}

export async function updateCompiledSkill(
  projectId: string,
  releaseId: string,
  compiledSkillId: string,
  body: {
    exposure_type?: string;
    risk_level?: string;
    status?: string;
    summary?: string | null;
    skill_body?: string | null;
    /** SKILL routing metadata (lists + invoke_first); persisted and merged into resource MCP schema. */
    routing?: {
      use_when?: string[];
      avoid_when?: string[];
      failure_modes?: string[];
      invoke_first?: boolean;
    };
    /** When true, `schema_json` is applied (use empty string to rebuild defaults). */
    replace_schema?: boolean;
    schema_json?: string | null;
  }
): Promise<CompiledSkill> {
  return api.patch<CompiledSkill>(
    `/projects/${projectId}/releases/${releaseId}/compiled-skills/${compiledSkillId}`,
    body
  );
}

export async function fetchApiKeys(projectId: string): Promise<ApiKey[]> {
  const response = await api.get<ApiKey[] | { api_keys: ApiKey[] }>(
    `/projects/${projectId}/api-keys`
  );
  if (Array.isArray(response)) return response;
  return response.api_keys ?? [];
}

export async function createApiKey(
  projectId: string,
  data?: { name?: string | null }
): Promise<{ key: string; prefix: string; name?: string | null }> {
  return api.post<{ key: string; prefix: string; name?: string | null }>(
    `/projects/${projectId}/api-keys`,
    data ?? {}
  );
}

export async function fetchRequestLogs(
  projectId: string,
  params?: { limit?: number; offset?: number }
): Promise<RequestLog[]> {
  const q = new URLSearchParams();
  if (params?.limit != null) q.set("limit", String(params.limit));
  if (params?.offset != null) q.set("offset", String(params.offset));
  const search = q.toString() ? `?${q.toString()}` : "";
  const response = await api.get<RequestLog[] | { logs: RequestLog[] }>(
    `/projects/${projectId}/request-logs${search}`
  );
  if (Array.isArray(response)) return response;
  return response.logs ?? [];
}
