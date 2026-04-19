"use client";

import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { fetchCompiledSkills, fetchReleaseValidation } from "@/lib/projects-api";
import { ApiError, formatApiErrorDetail } from "@/lib/api";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import {
  Table,
  TableBody,
  TableCaption,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { Skeleton } from "@/components/ui/skeleton";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";
import { pluralEn } from "@/lib/pluralize";
import type { CompiledSkill, ValidationErrorEntry } from "@/lib/types";
import type { McpMetadataFieldId } from "@/lib/mcp-metadata-editor-validation";
import {
  findCompiledSkillForValidationPath,
  mcpFieldForValidationIssue,
  mcpFieldShortLabel,
} from "@/lib/validation-mcp-deeplink";

function ValidationMessageCell({ message }: { message: string }) {
  const [expanded, setExpanded] = useState(false);
  const lines = message.split("\n").length;
  const long = message.length > 320 || lines > 5;
  if (!long) {
    return <span className="text-muted-foreground whitespace-pre-wrap">{message}</span>;
  }
  return (
    <div className="space-y-1.5">
      <p
        className={cn(
          "text-muted-foreground break-words",
          expanded ? "max-h-[min(40vh,16rem)] overflow-y-auto whitespace-pre-wrap" : "line-clamp-4"
        )}
      >
        {message}
      </p>
      <button
        type="button"
        className="text-primary text-xs font-medium hover:underline"
        onClick={() => setExpanded((e) => !e)}
      >
        {expanded ? "Show Less" : "Show Full Message"}
      </button>
    </div>
  );
}

function StructuredValidationEntryCell({
  entry,
  compiledSkills,
  onFixInMcp,
}: {
  entry: ValidationErrorEntry;
  compiledSkills?: CompiledSkill[];
  /** When set, every row gets a deep link: resolved skill opens that field; otherwise opens the release MCP list with the same field target. */
  onFixInMcp?: (target: { skillId: string | null; field: McpMetadataFieldId }) => void;
}) {
  const summary =
    entry.summary?.trim() ||
    (entry.message.includes(" — ")
      ? entry.message.split(" — ")[0]?.trim()
      : entry.message);
  const fix = entry.fix_hint?.trim();
  const metaParts = [
    entry.code ? entry.code : null,
    entry.line != null && entry.line > 0 ? `line ${entry.line}` : null,
  ].filter(Boolean);
  const meta = metaParts.join(" · ");
  const body = [summary, fix].filter(Boolean).join("\n\n");
  const skill = findCompiledSkillForValidationPath(compiledSkills, entry.path);
  const field = mcpFieldForValidationIssue(entry);
  const fieldLabel = mcpFieldShortLabel(field);
  return (
    <div className="space-y-1.5">
      {meta ? (
        <p className="text-muted-foreground font-mono text-xs leading-snug">{meta}</p>
      ) : null}
      {fix ? (
        <>
          <p className="text-sm font-medium leading-snug">{summary}</p>
          <p className="text-muted-foreground text-sm leading-snug">{fix}</p>
        </>
      ) : (
        <ValidationMessageCell message={body || entry.message} />
      )}
      {onFixInMcp ? (
        <Button
          type="button"
          variant="link"
          className="h-auto justify-start p-0 text-xs font-medium"
          onClick={() =>
            onFixInMcp({
              skillId: skill?.id ?? null,
              field,
            })
          }
          aria-label={
            skill
              ? `Open MCP metadata editor — ${fieldLabel}`
              : `Open MCP metadata for this release (no matching synced skill for this path) — ${fieldLabel}`
          }
        >
          {skill ? (
            <>Open in MCP metadata editor — {fieldLabel}</>
          ) : (
            <>Open MCP metadata — {fieldLabel}</>
          )}
        </Button>
      ) : null}
    </div>
  );
}

interface ReleaseValidationDialogProps {
  projectId: string;
  releaseId: string | null;
  releaseLabel: string;
  /** Short pipeline/ingest summary from the release row (full text shown here; table loads from API). */
  pipelineSummary?: string | null;
  open: boolean;
  onOpenChange: (open: boolean) => void;
  /** Opens the MCP metadata dialog for this release; `skillId` null = skill list (path did not match a compiled row). */
  onNavigateToMcpEditor?: (target: {
    skillId: string | null;
    field: McpMetadataFieldId;
  }) => void;
}

export function ReleaseValidationDialog({
  projectId,
  releaseId,
  releaseLabel,
  pipelineSummary,
  open,
  onOpenChange,
  onNavigateToMcpEditor,
}: ReleaseValidationDialogProps) {
  const [showFullSummary, setShowFullSummary] = useState(false);

  const { data, isLoading, error } = useQuery({
    queryKey: ["release-validation", projectId, releaseId],
    queryFn: () => fetchReleaseValidation(projectId, releaseId!),
    enabled: open && !!releaseId,
  });

  const { data: compiledSkills } = useQuery({
    queryKey: ["compiled-skills", projectId, releaseId],
    queryFn: () => fetchCompiledSkills(projectId, releaseId!),
    enabled: open && !!releaseId,
  });

  function handleFixInMcp(target: { skillId: string | null; field: McpMetadataFieldId }) {
    onNavigateToMcpEditor?.(target);
  }

  return (
    <Dialog
      open={open}
      onOpenChange={(next) => {
        if (!next) setShowFullSummary(false);
        onOpenChange(next);
      }}
    >
      <DialogContent className="grid max-h-[min(92vh,100dvh)] min-h-0 grid-rows-[auto_minmax(0,1fr)] gap-4 overflow-hidden p-6">
        <div className="min-w-0">
          <DialogHeader className="space-y-2">
            <DialogTitle>Release Errors — {releaseLabel}</DialogTitle>
            <DialogDescription>
              Validation report and pipeline messages for this release. Fix skills in the repo
              and sync again, or adjust MCP metadata if exposure is wrong.
            </DialogDescription>
          </DialogHeader>
          {pipelineSummary?.trim() ? (
            <div className="mt-4 space-y-2 rounded-lg border bg-muted/40 p-3">
              <div className="flex flex-wrap items-center justify-between gap-2">
                <p className="text-xs font-medium text-muted-foreground">Ingest / Pipeline Summary</p>
                <Button
                  type="button"
                  variant="ghost"
                  size="sm"
                  className="h-7 text-xs"
                  onClick={() => setShowFullSummary((v) => !v)}
                >
                  {showFullSummary ? "Show Less" : "Show Full Text"}
                </Button>
              </div>
              <pre
                className={`text-muted-foreground overflow-auto whitespace-pre-wrap break-words text-xs leading-relaxed ${
                  showFullSummary ? "max-h-[min(50vh,24rem)]" : "line-clamp-2 max-h-[2.75rem]"
                }`}
              >
                {pipelineSummary.trim()}
              </pre>
            </div>
          ) : null}
        </div>
        <div className="min-h-0 min-w-0 overflow-y-auto overscroll-contain pr-1 [-ms-overflow-style:auto] [scrollbar-gutter:stable]">
          {!releaseId ? null : isLoading ? (
            <Skeleton className="h-48" />
          ) : error ? (
            <div className="space-y-2 rounded-md border border-destructive/50 bg-destructive/10 p-3 text-sm text-destructive">
              <p className="font-medium">Could not load validation report.</p>
              {error instanceof ApiError ? (
                <pre className="max-h-40 overflow-auto whitespace-pre-wrap break-all text-xs text-destructive/85">
                  {formatApiErrorDetail(error.body) || error.message}
                </pre>
              ) : null}
            </div>
          ) : data ? (
            <div className="flex flex-col gap-4">
            <div className="flex shrink-0 flex-wrap items-center gap-2">
              <span className="text-sm font-medium">Report</span>
              <Badge
                variant={data.is_valid ? "default" : "destructive"}
                className={
                  data.is_valid
                    ? undefined
                    : "border-destructive/50 bg-destructive/10 text-destructive dark:bg-destructive/10"
                }
              >
                {data.is_valid ? "valid" : "invalid"}
              </Badge>
              <span className="text-muted-foreground text-sm">
                {data.errors.length.toLocaleString()}{" "}
                {pluralEn(data.errors.length, "error", "errors")}
              </span>
              {(data.warnings?.length ?? 0) > 0 ? (
                <span className="text-muted-foreground text-sm">
                  · {(data.warnings?.length ?? 0).toLocaleString()}{" "}
                  {pluralEn(data.warnings?.length ?? 0, "warning", "warnings")}
                </span>
              ) : null}
            </div>
            {(data.warnings?.length ?? 0) > 0 ? (
              <div className="shrink-0 space-y-2 rounded-lg border border-amber-500/35 bg-amber-500/10 p-3">
                <p className="text-sm font-medium text-amber-950 dark:text-amber-100">Warnings</p>
                <p className="text-muted-foreground text-xs leading-snug">
                  These skills were ingested but may need attention (for example, add YAML front matter in the
                  repo).
                </p>
                <Table className="table-fixed">
                  <TableCaption className="sr-only">
                    Validation warnings by skill path and message.
                  </TableCaption>
                  <TableHeader>
                    <TableRow>
                      <TableHead className="w-[34%] font-medium whitespace-normal">Path</TableHead>
                      <TableHead className="font-medium whitespace-normal">Details</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {(data.warnings ?? []).map((w, i) => (
                      <TableRow key={`w-${w.path}-${i}`}>
                        <TableCell className="w-[34%] min-w-0 align-top whitespace-normal break-all font-mono text-xs">
                          {w.path}
                        </TableCell>
                        <TableCell className="min-w-0 align-top whitespace-normal break-words text-sm leading-snug">
                          <StructuredValidationEntryCell
                            entry={w}
                            compiledSkills={compiledSkills}
                            onFixInMcp={onNavigateToMcpEditor ? handleFixInMcp : undefined}
                          />
                        </TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              </div>
            ) : null}
            {data.errors.length === 0 ? (
              <p className="text-muted-foreground text-sm">No structured errors.</p>
            ) : (
              <div className="overflow-hidden rounded-lg border border-destructive/50 bg-destructive/10">
                <Table className="table-fixed">
                  <TableCaption className="sr-only">
                    Validation errors by path or source and message.
                  </TableCaption>
                  <TableHeader>
                    <TableRow className="border-destructive/20 bg-destructive/5 hover:bg-destructive/5">
                      <TableHead className="w-[34%] font-medium whitespace-normal">
                        Path / Source
                      </TableHead>
                      <TableHead className="font-medium whitespace-normal">Details</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {data.errors.map((e, i) => (
                      <TableRow
                        key={`${e.path}-${i}`}
                        className="border-destructive/15 hover:bg-destructive/5"
                      >
                        <TableCell className="w-[34%] min-w-0 align-top whitespace-normal break-all font-mono text-xs text-foreground">
                          {e.path}
                        </TableCell>
                        <TableCell className="min-w-0 align-top whitespace-normal break-words text-sm leading-snug text-foreground">
                          <StructuredValidationEntryCell
                            entry={e}
                            compiledSkills={compiledSkills}
                            onFixInMcp={onNavigateToMcpEditor ? handleFixInMcp : undefined}
                          />
                        </TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              </div>
            )}
            </div>
          ) : null}
        </div>
      </DialogContent>
    </Dialog>
  );
}
