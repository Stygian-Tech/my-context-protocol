"use client";

import { useState } from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { fetchReleases, activateRelease } from "@/lib/projects-api";
import { ReleaseSkillMetadataDialog } from "@/components/dashboard/release-skill-metadata-dialog";
import { ReleaseValidationDialog } from "@/components/dashboard/release-validation-dialog";
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
  const [metaOpen, setMetaOpen] = useState(false);
  const [metaReleaseId, setMetaReleaseId] = useState<string | null>(null);
  const [validationOpen, setValidationOpen] = useState(false);
  const [validationCtx, setValidationCtx] = useState<{
    id: string;
    label: string;
    pipelineSummary: string | null;
  } | null>(null);

  function openValidationDialog(release: {
    id: string;
    commit_sha: string;
    error_summary?: string | null;
  }) {
    setValidationCtx({
      id: release.id,
      label: release.commit_sha.slice(0, 7),
      pipelineSummary: release.error_summary ?? null,
    });
    setValidationOpen(true);
  }

  const { data: releases, isLoading } = useQuery({
    queryKey: ["releases", projectId],
    queryFn: () => fetchReleases(projectId),
  });

  const activateMutation = useMutation({
    mutationFn: (releaseId: string) => activateRelease(projectId, releaseId),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["releases", projectId] });
      queryClient.invalidateQueries({ queryKey: ["project-catalog", projectId] });
      queryClient.invalidateQueries({ queryKey: ["project", projectId] });
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
            <TableHead className="w-[140px]">Actions</TableHead>
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
              <TableCell className="max-w-[14rem] align-top sm:max-w-[18rem]">
                {release.error_summary?.trim() ? (
                  <button
                    type="button"
                    onClick={() => openValidationDialog(release)}
                    className="group w-full rounded-md text-left transition-colors hover:bg-muted/60 focus-visible:ring-2 focus-visible:ring-ring"
                  >
                    <p className="text-muted-foreground line-clamp-2 text-sm leading-snug whitespace-pre-wrap break-words">
                      {release.error_summary.trim()}
                    </p>
                    <span className="mt-1 inline-block text-xs font-medium text-primary underline-offset-4 group-hover:underline">
                      View full report
                    </span>
                  </button>
                ) : release.status === "failed" ? (
                  <button
                    type="button"
                    onClick={() => openValidationDialog(release)}
                    className="text-sm font-medium text-primary underline-offset-4 hover:underline"
                  >
                    View details
                  </button>
                ) : (
                  <span className="text-muted-foreground text-sm">—</span>
                )}
              </TableCell>
              <TableCell>
                <div className="flex flex-col gap-1">
                  {release.status === "ready" ? (
                    <Button
                      size="sm"
                      variant="outline"
                      onClick={() => activateMutation.mutate(release.id)}
                      disabled={activateMutation.isPending}
                    >
                      Activate
                    </Button>
                  ) : null}
                  <Button
                    size="sm"
                    variant="outline"
                    onClick={() => {
                      setMetaReleaseId(release.id);
                      setMetaOpen(true);
                    }}
                  >
                    MCP metadata
                  </Button>
                  {release.status === "failed" && !release.error_summary?.trim() ? (
                    <Button
                      size="sm"
                      variant="secondary"
                      className="border-destructive/30 text-destructive hover:bg-destructive/10"
                      onClick={() => openValidationDialog(release)}
                    >
                      Errors
                    </Button>
                  ) : null}
                </div>
              </TableCell>
            </TableRow>
          ))}
        </TableBody>
      </Table>
      {releases.some((r) => r.status === "failed") && (
        <p className="text-muted-foreground text-sm leading-relaxed">
          Failed releases show a short error in the table — click{" "}
          <span className="font-medium text-foreground">View full report</span> to open the validation
          dialog.
        </p>
      )}
      <ReleaseSkillMetadataDialog
        projectId={projectId}
        releaseId={metaReleaseId}
        open={metaOpen}
        onOpenChange={(open) => {
          setMetaOpen(open);
          if (!open) setMetaReleaseId(null);
        }}
      />
      <ReleaseValidationDialog
        projectId={projectId}
        releaseId={validationCtx?.id ?? null}
        releaseLabel={validationCtx?.label ?? ""}
        pipelineSummary={validationCtx?.pipelineSummary ?? null}
        open={validationOpen}
        onOpenChange={(open) => {
          setValidationOpen(open);
          if (!open) setValidationCtx(null);
        }}
      />
    </div>
  );
}
