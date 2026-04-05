"use client";

import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { fetchReleaseValidation } from "@/lib/projects-api";
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

interface ReleaseValidationDialogProps {
  projectId: string;
  releaseId: string | null;
  releaseLabel: string;
  /** Short pipeline/ingest summary from the release row (full text shown here; table loads from API). */
  pipelineSummary?: string | null;
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

export function ReleaseValidationDialog({
  projectId,
  releaseId,
  releaseLabel,
  pipelineSummary,
  open,
  onOpenChange,
}: ReleaseValidationDialogProps) {
  const [showFullSummary, setShowFullSummary] = useState(false);

  const { data, isLoading, error } = useQuery({
    queryKey: ["release-validation", projectId, releaseId],
    queryFn: () => fetchReleaseValidation(projectId, releaseId!),
    enabled: open && !!releaseId,
  });

  return (
    <Dialog
      open={open}
      onOpenChange={(next) => {
        if (!next) setShowFullSummary(false);
        onOpenChange(next);
      }}
    >
      <DialogContent className="flex max-h-[92vh] w-[min(72rem,calc(100vw-1rem))] flex-col gap-4 overflow-hidden p-6">
        <DialogHeader>
          <DialogTitle>Release Errors — {releaseLabel}</DialogTitle>
          <DialogDescription>
            Validation report and pipeline messages for this release. Fix skills in the repo
            and sync again, or adjust MCP metadata if exposure is wrong.
          </DialogDescription>
        </DialogHeader>
        {pipelineSummary?.trim() ? (
          <div className="shrink-0 space-y-2 rounded-lg border bg-muted/40 p-3">
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
        {!releaseId ? null : isLoading ? (
          <Skeleton className="h-48 shrink-0" />
        ) : error ? (
          <div className="space-y-2 rounded-md border border-destructive/40 bg-destructive/5 p-3 text-sm">
            <p className="font-medium text-destructive">Could not load validation report.</p>
            {error instanceof ApiError ? (
              <pre className="text-muted-foreground max-h-40 overflow-auto whitespace-pre-wrap break-all text-xs">
                {formatApiErrorDetail(error.body) || error.message}
              </pre>
            ) : null}
          </div>
        ) : data ? (
          <div className="flex min-h-0 flex-1 flex-col gap-4 overflow-y-auto overscroll-contain">
            <div className="flex shrink-0 flex-wrap items-center gap-2">
              <span className="text-sm font-medium">Report</span>
              <Badge variant={data.is_valid ? "default" : "destructive"}>
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
                  <TableHeader>
                    <TableRow>
                      <TableHead className="w-[34%] font-medium whitespace-normal">Path</TableHead>
                      <TableHead className="font-medium whitespace-normal">Message</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {(data.warnings ?? []).map((w, i) => (
                      <TableRow key={`w-${w.path}-${i}`}>
                        <TableCell className="w-[34%] min-w-0 align-top whitespace-normal break-all font-mono text-xs">
                          {w.path}
                        </TableCell>
                        <TableCell className="min-w-0 align-top whitespace-normal break-words text-sm leading-snug">
                          <ValidationMessageCell message={w.message} />
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
              <Table className="table-fixed">
                <TableHeader>
                  <TableRow>
                    <TableHead className="w-[34%] font-medium whitespace-normal">
                      Path / Source
                    </TableHead>
                    <TableHead className="font-medium whitespace-normal">Message</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {data.errors.map((e, i) => (
                    <TableRow key={`${e.path}-${i}`}>
                      <TableCell className="w-[34%] min-w-0 align-top whitespace-normal break-all font-mono text-xs">
                        {e.path}
                      </TableCell>
                      <TableCell className="min-w-0 align-top whitespace-normal break-words text-sm leading-snug">
                        <ValidationMessageCell message={e.message} />
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            )}
          </div>
        ) : null}
      </DialogContent>
    </Dialog>
  );
}
