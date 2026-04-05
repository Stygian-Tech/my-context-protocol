"use client";

import { useState } from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import {
  fetchReleases,
  fetchCompiledSkills,
  activateRelease,
} from "@/lib/projects-api";
import type { McpMetadataFieldId } from "@/lib/mcp-metadata-editor-validation";
import {
  metadataHealthTier,
  mcpFocusFieldForBlockingSkill,
} from "@/lib/mcp-metadata-health";
import { ReleaseBodyChangesDialog } from "@/components/dashboard/release-body-changes-dialog";
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
import { Badge, badgeVariants } from "@/components/ui/badge";
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
  const [bodyDiffOpen, setBodyDiffOpen] = useState(false);
  const [bodyDiffCtx, setBodyDiffCtx] = useState<{
    releaseId: string;
    label: string;
  } | null>(null);
  const [mcpInitialFocus, setMcpInitialFocus] = useState<{
    skillId: string;
    field: McpMetadataFieldId;
  } | null>(null);

  function openMcpToFirstBlockingSkill(releaseId: string) {
    void (async () => {
      try {
        const list = await queryClient.fetchQuery({
          queryKey: ["compiled-skills", projectId, releaseId],
          queryFn: () => fetchCompiledSkills(projectId, releaseId),
        });
        const firstRed = list.find((s) => metadataHealthTier(s) === "red");
        setMcpInitialFocus(
          firstRed
            ? {
                skillId: firstRed.id,
                field: mcpFocusFieldForBlockingSkill(firstRed),
              }
            : null,
        );
      } catch {
        setMcpInitialFocus(null);
      }
      setMetaReleaseId(releaseId);
      setMetaOpen(true);
    })();
  }

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
      queryClient.invalidateQueries({
        queryKey: ["project-catalog", projectId],
      });
      queryClient.invalidateQueries({ queryKey: ["project", projectId] });
      queryClient.invalidateQueries({
        queryKey: ["project-dashboard-summary", projectId],
      });
      queryClient.invalidateQueries({
        queryKey: ["account-dashboard-summary"],
      });
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

  const failedReleaseCount = releases.filter(
    (r) => r.status === "failed",
  ).length;

  return (
    <div className="space-y-4">
      <Table>
        <TableCaption className="sr-only">
          Project releases: commit, status, created time, pipeline errors, MCP
          metadata health summaries, and actions including activate and MCP
          metadata editor.
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
            const mcBlock = release.mcp_metadata_blocking_skills ?? 0;
            const mcWarn = release.mcp_metadata_warning_skills ?? 0;
            const hasMcpMetadataIssues = mcBlock > 0 || mcWarn > 0;
            const useTopErrorCell = Boolean(errSummary) || hasMcpMetadataIssues;
            const bodyChanges = release.skill_body_changes_count ?? 0;

            return (
              <TableRow key={release.id}>
                <TableCell className="font-mono text-sm align-middle">
                  <div className="flex flex-wrap items-start justify-start gap-1.5">
                    <span>{shortCommitLabel(release.commit_sha)}</span>
                    {bodyChanges > 0 ? (
                      <button
                        type="button"
                        className={cn(
                          badgeVariants({ variant: "outline" }),
                          "h-5 cursor-pointer px-1.5 text-[0.65rem] font-normal hover:bg-muted/80",
                        )}
                        onClick={() => {
                          setBodyDiffCtx({
                            releaseId: release.id,
                            label: shortCommitLabel(release.commit_sha),
                          });
                          setBodyDiffOpen(true);
                        }}
                        aria-label={`View ${bodyChanges} SKILL body ${pluralEn(bodyChanges, "change", "changes")} vs. prior release for ${shortCommitLabel(release.commit_sha)}`}
                      >
                        {bodyChanges}{" "}
                        {pluralEn(bodyChanges, "body change", "body changes")}
                      </button>
                    ) : null}
                  </div>
                </TableCell>
                <TableCell className="align-middle">
                  <div className="flex flex-wrap items-start justify-start gap-1.5">
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
                    "max-w-[14rem] whitespace-normal sm:max-w-[18rem]",
                    useTopErrorCell ? "align-top" : "align-middle",
                  )}
                >
                  <div className="flex flex-col items-center gap-2">
                    {errSummary ? (
                      <button
                        type="button"
                        onClick={() => openValidationDialog(release)}
                        className="group w-full self-stretch rounded-md text-left transition-colors hover:bg-muted/60 focus-visible:ring-2 focus-visible:ring-ring"
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
                        className="w-fit self-center text-sm font-medium text-primary underline-offset-4 hover:underline"
                      >
                        View Details
                      </button>
                    ) : null}
                    {hasMcpMetadataIssues ? (
                      <>
                        {mcBlock > 0 ? (
                          <button
                            type="button"
                            onClick={() =>
                              openMcpToFirstBlockingSkill(release.id)
                            }
                            className={cn(
                              "w-fit max-w-full rounded-md border px-2.5 py-2 text-center text-xs leading-snug transition-colors",
                              "border-destructive/50 bg-destructive/10 text-destructive",
                              "hover:bg-destructive/15 focus-visible:ring-2 focus-visible:ring-ring focus-visible:outline-none",
                            )}
                          >
                            <p className="font-medium">
                              {mcBlock} {pluralEn(mcBlock, "skill", "skills")}{" "}
                              blocking MCP publish
                            </p>
                            {mcWarn > 0 ? (
                              <p className="mt-1 text-[0.7rem] font-medium text-amber-900/95 dark:text-amber-100/95">
                                + {mcWarn} more with warnings only
                              </p>
                            ) : null}
                          </button>
                        ) : null}
                        {mcBlock === 0 && mcWarn > 0 ? (
                          <div className="w-fit max-w-full rounded-md border border-amber-500/40 bg-amber-500/10 px-2.5 py-2 text-center text-xs leading-snug text-amber-950 dark:text-amber-50">
                            <p className="font-medium text-amber-900 dark:text-amber-100">
                              {mcWarn} {pluralEn(mcWarn, "skill", "skills")}{" "}
                              need MCP review
                            </p>
                          </div>
                        ) : null}
                      </>
                    ) : null}
                    {!errSummary &&
                    release.status !== "failed" &&
                    !hasMcpMetadataIssues ? (
                      <span className="text-muted-foreground self-center text-sm">—</span>
                    ) : null}
                  </div>
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
                    <div className="flex flex-wrap items-start justify-start gap-1.5">
                      <Button
                        size="sm"
                        variant="outline"
                        onClick={() => {
                          setMcpInitialFocus(null);
                          setMetaReleaseId(release.id);
                          setMetaOpen(true);
                        }}
                        aria-label={
                          hasMcpMetadataIssues
                            ? [
                                "MCP Metadata",
                                mcBlock > 0 ? `${mcBlock} blocking` : null,
                                mcWarn > 0 ? `${mcWarn} warnings` : null,
                              ]
                                .filter(Boolean)
                                .join(", ")
                            : "MCP Metadata"
                        }
                      >
                        MCP Metadata
                      </Button>
                      {mcWarn > 0 ? (
                        <span
                          className={cn(
                            "inline-flex min-h-7 min-w-7 shrink-0 items-center justify-center rounded-md border px-1.5 text-xs font-medium leading-snug tabular-nums",
                            "border-amber-500/40 bg-amber-500/10 text-amber-950 dark:text-amber-50",
                          )}
                          aria-hidden
                          title={`${mcWarn} with warnings only`}
                        >
                          {mcWarn}
                        </span>
                      ) : null}
                    </div>
                    {release.status === "failed" &&
                    !release.error_summary?.trim() ? (
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
          {failedReleaseCount.toLocaleString()} failed{" "}
          {pluralEn(failedReleaseCount, "release", "releases")}{" "}
          {pluralEn(failedReleaseCount, "shows", "show")} a short error in the
          table — click{" "}
          <span className="font-medium text-foreground">View Full Report</span>{" "}
          to open the validation dialog.
        </p>
      ) : null}
      <ReleaseSkillMetadataDialog
        projectId={projectId}
        releaseId={metaReleaseId}
        open={metaOpen}
        initialMcpFocus={mcpInitialFocus}
        onOpenChange={(open) => {
          setMetaOpen(open);
          if (!open) {
            setMetaReleaseId(null);
            setMcpInitialFocus(null);
          }
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
      <ReleaseBodyChangesDialog
        projectId={projectId}
        releaseId={bodyDiffCtx?.releaseId ?? null}
        releaseLabel={bodyDiffCtx?.label ?? ""}
        open={bodyDiffOpen}
        onOpenChange={(open) => {
          setBodyDiffOpen(open);
          if (!open) setBodyDiffCtx(null);
        }}
      />
    </div>
  );
}
