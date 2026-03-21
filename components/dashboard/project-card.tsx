"use client";

import Link from "next/link";
import { Card, CardContent, CardHeader } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import type { Project } from "@/lib/types";

interface ProjectCardProps {
  project: Project;
}

export function ProjectCard({ project }: ProjectCardProps) {
  return (
    <Link href={`/projects/${project.id}`}>
      <Card className="transition-colors hover:bg-muted/50">
        <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
          <h3 className="font-semibold">{project.name}</h3>
          <Badge variant="secondary">{project.slug}</Badge>
        </CardHeader>
        <CardContent>
          <p className="text-muted-foreground font-mono text-xs break-all">
            {project.mcp_url ?? "MCP URL not configured on server"}
          </p>
        </CardContent>
      </Card>
    </Link>
  );
}
