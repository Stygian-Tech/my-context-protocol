"use client";

import { useState } from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { fetchReleases, activateRelease } from "@/lib/projects-api";
import { ReleaseSkillMetadataDialog } from "@/components/dashboard/release-skill-metadata-dialog";
import { ReleaseValidationDialog } from "@/components/dashboard/release-validation-dialog";
import {
  Table,
  TableBody,
  TableCaption,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";
import type { ReleaseStatus } from "@/lib/types";
import { cn } from "@/lib/utils";
import { shortCommitLabel } from "@/lib/commit-display";
import { pluralEn } from "@/lib/pluralize";
import { formatLocalDateTime } from "@/lib/format-local-time";

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
      label: shortCommitLabel(release.commit_sha),
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
      queryClient.invalidateQueries({ queryKey: ["project-dashboard-summary", projectId] });
      queryClient.invalidateQueries({ queryKey: ["account-dashboard-summary"] });
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

  const failedReleaseCount = releases.filter((r) => r.status === "failed").length;

  return (
    <div className="space-y-4">
      <Table>
        <TableCaption className="sr-only">
          Project releases: commit, status, created time, errors, and actions
          including activate and MCP metadata.
        </TableCaption>
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
          {releases.map((release) => {
            const errSummary = release.error_summary?.trim();
            const useTopErrorCell = Boolean(errSummary);
            const bodyChanges = release.skill_body_changes_count ?? 0;
            return (
            <TableRow key={release.id}>
              <TableCell className="font-mono text-sm align-middle">
                <div className="flex flex-wrap items-center gap-1.5">
                  <span>{shortCommitLabel(release.commit_sha)}</span>
                  {bodyChanges > 0 ? (
                    <Badge variant="outline" className="h-5 px-1.5 text-[0.65rem] font-normal">
                      {bodyChanges} {pluralEn(bodyChanges, "body change", "body changes")}
                    </Badge>
                  ) : null}
                </div>
              </TableCell>
              <TableCell className="align-middle">
                <div className="flex flex-wrap items-center gap-1.5">
                  <Badge variant={statusVariant(release.status)}>
                    {release.status}
                  </Badge>
                  {release.is_active ? (
                    <Badge
                      variant="default"
                      className="border border-primary/30 bg-primary/15 text-primary"
                    >
                      Active
                    </Badge>
                  ) : null}
                </div>
              </TableCell>
              <TableCell className="align-middle">
                {formatLocalDateTime(release.created_at)}
              </TableCell>
              <TableCell
                className={cn(
                  "max-w-[14rem] sm:max-w-[18rem]",
                  useTopErrorCell ? "align-top" : "align-middle"
                )}
              >
                {errSummary ? (
                  <button
                    type="button"
                    onClick={() => openValidationDialog(release)}
                    className="group w-full rounded-md text-left transition-colors hover:bg-muted/60 focus-visible:ring-2 focus-visible:ring-ring"
                  >
                    <p className="text-muted-foreground line-clamp-2 text-sm leading-snug whitespace-pre-wrap break-words">
                      {errSummary}
                    </p>
                    <span className="mt-1 inline-block text-xs font-medium text-primary underline-offset-4 group-hover:underline">
                      View Full Report
                    </span>
                  </button>
                ) : release.status === "failed" ? (
                  <button
                    type="button"
                    onClick={() => openValidationDialog(release)}
                    className="text-sm font-medium text-primary underline-offset-4 hover:underline"
                  >
                    View Details
                  </button>
                ) : (
                  <span className="text-muted-foreground text-sm">—</span>
                )}
              </TableCell>
              <TableCell className="align-middle">
                <div className="flex flex-col gap-1">
                  {release.status === "ready" && !release.is_active ? (
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
                    MCP Metadata
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
          );
          })}
        </TableBody>
      </Table>
      {failedReleaseCount > 0 ? (
        <p className="text-muted-foreground text-sm leading-relaxed">
          {failedReleaseCount.toLocaleString()} failed {pluralEn(failedReleaseCount, "release", "releases")}{" "}
          {pluralEn(failedReleaseCount, "shows", "show")} a short error in the table — click{" "}
          <span className="font-medium text-foreground">View Full Report</span> to open the validation
          dialog.
        </p>
      ) : null}
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
