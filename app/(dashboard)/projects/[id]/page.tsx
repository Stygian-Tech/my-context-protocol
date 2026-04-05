"use client";

import { useParams } from "next/navigation";
import { useQuery } from "@tanstack/react-query";
import { fetchProject } from "@/lib/projects-api";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Skeleton } from "@/components/ui/skeleton";
import { RepoConnectionSection } from "@/components/dashboard/repo-connection-section";
import { ReleaseTable } from "@/components/dashboard/release-table";
import { ApiKeyManager } from "@/components/dashboard/api-key-manager";
import { RequestLogsTable } from "@/components/dashboard/request-logs-table";
import { CustomDomainSection } from "@/components/dashboard/custom-domain-section";
import { McpCatalogSection } from "@/components/dashboard/mcp-catalog-section";
import { ProjectOverviewMetrics } from "@/components/dashboard/project-overview-metrics";
import { useAuth } from "@/contexts/auth-context";
import { ApiError, formatApiErrorDetail } from "@/lib/api";
import { Button } from "@/components/ui/button";
import { CopyIcon } from "lucide-react";
import { copyTextToClipboard } from "@/lib/clipboard";

export default function ProjectDetailPage() {
  const { user } = useAuth();
  const params = useParams();
  const projectId = params.id as string;

  const { data: project, isLoading, error } = useQuery({
    queryKey: ["project", projectId],
    queryFn: () => fetchProject(projectId),
    enabled: !!projectId,
  });

  if (isLoading || !project) {
    return (
      <div
        className="space-y-6"
        role="status"
        aria-live="polite"
        aria-busy="true"
      >
        <Skeleton className="h-8 w-64" />
        <Skeleton className="h-64" />
      </div>
    );
  }

  if (error) {
    return (
      <div className="space-y-2 rounded-md border border-destructive/40 bg-destructive/5 p-4 text-sm">
        <p className="font-medium text-destructive">Failed to load project.</p>
        {error instanceof ApiError ? (
          <pre className="text-muted-foreground max-h-48 overflow-auto whitespace-pre-wrap break-all text-xs">
            {formatApiErrorDetail(error.body) || error.message}
          </pre>
        ) : (
          <p className="text-muted-foreground text-xs">{String(error)}</p>
        )}
      </div>
    );
  }

  return (
    <div className="space-y-6 md:space-y-7">
      <div className="space-y-2">
        <h1 className="text-3xl font-bold tracking-tight">{project.name}</h1>
        <div className="flex flex-col gap-2 sm:flex-row sm:items-start sm:justify-between">
          <p className="text-muted-foreground font-mono text-sm leading-relaxed break-all">
            {project.mcp_url ??
              "MCP URL unavailable — set SAAS_MCP_BASE_DOMAIN on the server (or verify a custom domain)."}
          </p>
          {project.mcp_url ? (
            <Button
              type="button"
              variant="outline"
              size="sm"
              className="shrink-0"
              onClick={() =>
                void copyTextToClipboard(project.mcp_url!, {
                  success: "MCP URL copied to clipboard",
                  error: "Could not copy MCP URL",
                })
              }
            >
              <CopyIcon className="mr-1 h-3.5 w-3.5" aria-hidden />
              Copy MCP URL
            </Button>
          ) : null}
        </div>
      </div>
      <Tabs defaultValue="overview">
        <TabsList>
          <TabsTrigger value="overview">Overview</TabsTrigger>
          <TabsTrigger value="repo">Repo</TabsTrigger>
          <TabsTrigger value="releases">Releases</TabsTrigger>
          <TabsTrigger value="api-keys">API Keys</TabsTrigger>
          <TabsTrigger value="logs">Logs</TabsTrigger>
        </TabsList>
        <TabsContent value="overview" className="space-y-4">
          <ProjectOverviewMetrics projectId={projectId} />
          <div className="rounded-lg border p-4">
            <h3 className="font-medium">Project Info</h3>
            <dl className="mt-2 space-y-1 text-sm">
              <div>
                <dt className="text-muted-foreground inline">Slug: </dt>
                <dd className="inline">{project.slug}</dd>
              </div>
              <div>
                <dt className="text-muted-foreground inline">Platform subdomain: </dt>
                <dd className="inline">{project.subdomain}</dd>
              </div>
              <div>
                <dt className="text-muted-foreground inline">MCP URL: </dt>
                <dd className="inline font-mono break-all">
                  {project.mcp_url ??
                    "— (configure SAAS_MCP_BASE_DOMAIN or verify custom domain)"}
                </dd>
              </div>
            </dl>
          </div>
          <McpCatalogSection projectId={projectId} />
          {user?.plan === "pro" && <CustomDomainSection projectId={projectId} />}
        </TabsContent>
        <TabsContent value="repo">
          <RepoConnectionSection projectId={projectId} />
        </TabsContent>
        <TabsContent value="releases">
          <ReleaseTable projectId={projectId} />
        </TabsContent>
        <TabsContent value="api-keys">
          <ApiKeyManager
            projectId={projectId}
            mcpUrl={project.mcp_url}
            projectSlug={project.slug}
          />
        </TabsContent>
        <TabsContent value="logs">
          <RequestLogsTable projectId={projectId} />
        </TabsContent>
      </Tabs>
    </div>
  );
}
