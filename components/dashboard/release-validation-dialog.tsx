"use client";

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
  const { data, isLoading, error } = useQuery({
    queryKey: ["release-validation", projectId, releaseId],
    queryFn: () => fetchReleaseValidation(projectId, releaseId!),
    enabled: open && !!releaseId,
  });

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-h-[90vh] w-full max-w-[calc(100vw-2rem)] overflow-y-auto sm:max-w-[min(56rem,calc(100vw-2rem))]">
        <DialogHeader>
          <DialogTitle>Release errors — {releaseLabel}</DialogTitle>
          <DialogDescription>
            Validation report and pipeline messages for this release. Fix skills in the repo
            and sync again, or adjust MCP metadata if exposure is wrong.
          </DialogDescription>
        </DialogHeader>
        {pipelineSummary?.trim() ? (
          <div className="space-y-1.5 rounded-lg border bg-muted/40 p-3">
            <p className="text-xs font-medium text-muted-foreground">Ingest / pipeline summary</p>
            <pre className="text-muted-foreground max-h-48 overflow-auto whitespace-pre-wrap break-words text-xs leading-relaxed">
              {pipelineSummary.trim()}
            </pre>
          </div>
        ) : null}
        {!releaseId ? null : isLoading ? (
          <Skeleton className="h-48" />
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
          <div className="space-y-4">
            <div className="flex items-center gap-2">
              <span className="text-sm font-medium">Report</span>
              <Badge variant={data.is_valid ? "default" : "destructive"}>
                {data.is_valid ? "valid" : "invalid"}
              </Badge>
              <span className="text-muted-foreground text-sm">
                {data.errors.length} entr{data.errors.length === 1 ? "y" : "ies"}
              </span>
            </div>
            {data.errors.length === 0 ? (
              <p className="text-muted-foreground text-sm">No structured errors.</p>
            ) : (
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead className="w-[40%]">Path / source</TableHead>
                    <TableHead>Message</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {data.errors.map((e, i) => (
                    <TableRow key={`${e.path}-${i}`}>
                      <TableCell className="max-w-[200px] align-top font-mono text-xs break-all">
                        {e.path}
                      </TableCell>
                      <TableCell className="text-muted-foreground align-top text-sm whitespace-pre-wrap">
                        {e.message}
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
