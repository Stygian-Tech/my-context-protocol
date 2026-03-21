"use client";

import { useQuery } from "@tanstack/react-query";
import { fetchProjects } from "@/lib/projects-api";
import { ProjectCard } from "@/components/dashboard/project-card";
import { CreateProjectDialog } from "@/components/dashboard/create-project-dialog";
import { Skeleton } from "@/components/ui/skeleton";

export default function ProjectsPage() {
  const { data: projects, isLoading, error } = useQuery({
    queryKey: ["projects"],
    queryFn: fetchProjects,
  });

  if (isLoading) {
    return (
      <div className="space-y-7">
        <div className="flex flex-col gap-4 sm:flex-row sm:items-end sm:justify-between">
          <div>
            <Skeleton className="h-8 w-48" />
            <Skeleton className="mt-2 h-4 w-64" />
          </div>
        </div>
        <div className="grid gap-4 md:grid-cols-2 md:gap-5 lg:grid-cols-3">
          {[1, 2, 3].map((i) => (
            <Skeleton key={i} className="h-24" />
          ))}
        </div>
      </div>
    );
  }

  if (error) {
    return (
      <div className="rounded-md bg-destructive/10 p-4 text-destructive">
        Failed to load projects. Make sure the backend is running.
      </div>
    );
  }

  return (
    <div className="space-y-7">
      <div className="flex flex-col gap-4 sm:flex-row sm:items-end sm:justify-between">
        <div className="min-w-0 space-y-2">
          <h1 className="text-3xl font-bold tracking-tight">Projects</h1>
          <p className="max-w-xl text-muted-foreground leading-relaxed">
            Manage your MCP projects and skill repositories.
          </p>
        </div>
        <CreateProjectDialog />
      </div>
      {projects && projects.length > 0 ? (
        <div className="grid gap-4 md:grid-cols-2 md:gap-5 lg:grid-cols-3">
          {projects.map((project) => (
            <ProjectCard key={project.id} project={project} />
          ))}
        </div>
      ) : (
        <div className="flex flex-col items-center justify-center gap-6 rounded-lg border border-dashed px-6 py-10 text-center md:gap-8 md:py-12">
          <div className="max-w-sm space-y-3">
            <p className="text-muted-foreground text-base">
              No projects yet.
            </p>
            <p className="text-muted-foreground text-sm leading-relaxed">
              Create your first project to get started.
            </p>
          </div>
          <CreateProjectDialog />
        </div>
      )}
    </div>
  );
}
