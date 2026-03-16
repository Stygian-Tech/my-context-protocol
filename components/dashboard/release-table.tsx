"use client";

import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { fetchReleases, activateRelease } from "@/lib/projects-api";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";
import type { ReleaseStatus } from "@/lib/types";

interface ReleaseTableProps {
  projectId: string;
}

function statusVariant(status: ReleaseStatus) {
  switch (status) {
    case "ready":
      return "default";
    case "pending":
      return "secondary";
    case "failed":
      return "destructive";
    default:
      return "secondary";
  }
}

export function ReleaseTable({ projectId }: ReleaseTableProps) {
  const queryClient = useQueryClient();

  const { data: releases, isLoading } = useQuery({
    queryKey: ["releases", projectId],
    queryFn: () => fetchReleases(projectId),
  });

  const activateMutation = useMutation({
    mutationFn: (releaseId: string) => activateRelease(projectId, releaseId),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["releases", projectId] });
    },
  });

  if (isLoading) {
    return <Skeleton className="h-48" />;
  }

  if (!releases || releases.length === 0) {
    return (
      <div className="rounded-lg border p-8 text-center text-muted-foreground">
        No releases yet. Connect a repository and push to create your first
        release.
      </div>
    );
  }

  return (
    <div className="space-y-4">
      <Table>
        <TableHeader>
          <TableRow>
            <TableHead>Commit</TableHead>
            <TableHead>Status</TableHead>
            <TableHead>Created</TableHead>
            <TableHead>Error</TableHead>
            <TableHead className="w-[100px]">Actions</TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          {releases.map((release) => (
            <TableRow key={release.id}>
              <TableCell className="font-mono text-sm">
                {release.commit_sha.slice(0, 7)}
              </TableCell>
              <TableCell>
                <Badge variant={statusVariant(release.status)}>
                  {release.status}
                </Badge>
              </TableCell>
              <TableCell>
                {new Date(release.created_at).toLocaleString()}
              </TableCell>
              <TableCell className="max-w-[200px] truncate text-muted-foreground text-sm">
                {release.error_summary ?? "-"}
              </TableCell>
              <TableCell>
                {release.status === "ready" && (
                  <Button
                    size="sm"
                    variant="outline"
                    onClick={() => activateMutation.mutate(release.id)}
                    disabled={activateMutation.isPending}
                  >
                    Activate
                  </Button>
                )}
              </TableCell>
            </TableRow>
          ))}
        </TableBody>
      </Table>
      {releases.some((r) => r.status === "failed" && r.error_summary) && (
        <div className="rounded-lg border border-destructive/50 bg-destructive/5 p-4">
          <h4 className="font-medium text-destructive">Validation Report</h4>
          <p className="text-muted-foreground text-sm">
            Failed releases have validation errors. Check the error column for
            details.
          </p>
        </div>
      )}
    </div>
  );
}
