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

export default function ProjectDetailPage() {
  const params = useParams();
  const projectId = params.id as string;

  const { data: project, isLoading, error } = useQuery({
    queryKey: ["project", projectId],
    queryFn: () => fetchProject(projectId),
    enabled: !!projectId,
  });

  if (isLoading || !project) {
    return (
      <div className="space-y-6">
        <Skeleton className="h-8 w-64" />
        <Skeleton className="h-64" />
      </div>
    );
  }

  if (error) {
    return (
      <div className="rounded-md bg-destructive/10 p-4 text-destructive">
        Failed to load project.
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-3xl font-bold tracking-tight">{project.name}</h1>
        <p className="text-muted-foreground">
          {project.subdomain}.mcp.yourdomain.com
        </p>
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
          <div className="rounded-lg border p-4">
            <h3 className="font-medium">Project Info</h3>
            <dl className="mt-2 space-y-1 text-sm">
              <div>
                <dt className="text-muted-foreground inline">Slug: </dt>
                <dd className="inline">{project.slug}</dd>
              </div>
              <div>
                <dt className="text-muted-foreground inline">Subdomain: </dt>
                <dd className="inline">{project.subdomain}</dd>
              </div>
            </dl>
          </div>
        </TabsContent>
        <TabsContent value="repo">
          <RepoConnectionSection projectId={projectId} />
        </TabsContent>
        <TabsContent value="releases">
          <ReleaseTable projectId={projectId} />
        </TabsContent>
        <TabsContent value="api-keys">
          <ApiKeyManager projectId={projectId} />
        </TabsContent>
        <TabsContent value="logs">
          <RequestLogsTable projectId={projectId} />
        </TabsContent>
      </Tabs>
    </div>
  );
}
