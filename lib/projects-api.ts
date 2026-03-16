import { api } from "./api";
import type { Project, RepoConnection, Release, ApiKey, RequestLog } from "./types";

export async function fetchProjects(): Promise<Project[]> {
  const response = await api.get<Project[] | { projects: Project[] }>("/projects");
  if (Array.isArray(response)) return response;
  return response.projects ?? [];
}

export async function fetchProject(id: string): Promise<Project> {
  return api.get<Project>(`/projects/${id}`);
}

export async function createProject(data: {
  name: string;
  slug: string;
  subdomain: string;
}): Promise<Project> {
  return api.post<Project>("/projects", data);
}

export async function fetchRepoConnection(projectId: string): Promise<RepoConnection | null> {
  try {
    return await api.get<RepoConnection>(`/projects/${projectId}/repo-connection`);
  } catch {
    return null;
  }
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

export async function fetchApiKeys(projectId: string): Promise<ApiKey[]> {
  const response = await api.get<ApiKey[] | { api_keys: ApiKey[] }>(
    `/projects/${projectId}/api-keys`
  );
  if (Array.isArray(response)) return response;
  return response.api_keys ?? [];
}

export async function createApiKey(projectId: string): Promise<{ key: string; prefix: string }> {
  return api.post<{ key: string; prefix: string }>(`/projects/${projectId}/api-keys`);
}

export async function fetchRequestLogs(
  projectId: string,
  params?: { limit?: number; offset?: number }
): Promise<RequestLog[]> {
  const search = params
    ? `?${new URLSearchParams(params as Record<string, string>).toString()}`
    : "";
  const response = await api.get<RequestLog[] | { logs: RequestLog[] }>(
    `/projects/${projectId}/request-logs${search}`
  );
  if (Array.isArray(response)) return response;
  return response.logs ?? [];
}
