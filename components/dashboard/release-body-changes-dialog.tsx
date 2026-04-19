"use client";

import { useQuery } from "@tanstack/react-query";
import { fetchCompiledSkills } from "@/lib/projects-api";
import { ApiError, formatApiErrorDetail } from "@/lib/api";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Skeleton } from "@/components/ui/skeleton";

interface ReleaseBodyChangesDialogProps {
  projectId: string;
  releaseId: string | null;
  /** Short commit label for the release row (e.g. `abc1234`). */
  releaseLabel: string;
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

export function ReleaseBodyChangesDialog({
  projectId,
  releaseId,
  releaseLabel,
  open,
  onOpenChange,
}: ReleaseBodyChangesDialogProps) {
  const { data: skills, isLoading, error } = useQuery({
    queryKey: ["compiled-skills", projectId, releaseId],
    queryFn: () => fetchCompiledSkills(projectId, releaseId!),
    enabled: open && !!releaseId,
  });

  const withDiff =
    skills?.filter((s) => (s.body_diff_unified ?? "").trim().length > 0) ?? [];

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-h-[min(90vh,720px)] w-[min(100vw-2rem,56rem)] max-w-[min(100vw-2rem,56rem)] gap-0 overflow-hidden p-0">
        <DialogHeader className="border-b px-6 py-4">
          <DialogTitle>SKILL Body Changes</DialogTitle>
          <DialogDescription className="text-pretty">
            Unified diff vs. the prior release for each skill whose SKILL.md body changed in release{" "}
            <span className="font-mono font-medium text-foreground">{releaseLabel}</span>. Lines
            prefixed with <code className="text-foreground">-</code> / <code className="text-foreground">+</code>{" "}
            are removals and additions.
          </DialogDescription>
        </DialogHeader>
        <div className="max-h-[min(72vh,620px)] overflow-y-auto px-6 py-4">
          {isLoading ? (
            <div className="space-y-3">
              <Skeleton className="h-4 w-2/3" />
              <Skeleton className="h-32 w-full" />
              <Skeleton className="h-4 w-1/2" />
              <Skeleton className="h-24 w-full" />
            </div>
          ) : error ? (
            <div className="space-y-2 rounded-md border border-destructive/40 bg-destructive/5 p-4 text-sm">
              <p className="font-medium text-destructive">Could not load compiled skills.</p>
              {error instanceof ApiError ? (
                <pre className="text-muted-foreground max-h-40 overflow-auto whitespace-pre-wrap break-all text-xs">
                  {formatApiErrorDetail(error.body) || error.message}
                </pre>
              ) : (
                <p className="text-muted-foreground text-xs">{String(error)}</p>
              )}
            </div>
          ) : withDiff.length === 0 ? (
            <p className="text-muted-foreground text-sm leading-relaxed">
              No body diffs are stored for this release. Diffs appear when a skill&apos;s SKILL.md
              body changed relative to an earlier release that had a stored body.
            </p>
          ) : (
            <div className="space-y-8">
              {withDiff.map((skill) => (
                <section
                  key={skill.id}
                  aria-labelledby={`body-diff-heading-${skill.id}`}
                  className="space-y-2"
                >
                  <div className="space-y-0.5">
                    <h3
                      id={`body-diff-heading-${skill.id}`}
                      className="text-sm font-semibold text-foreground"
                    >
                      {skill.name}
                    </h3>
                    <p className="text-muted-foreground font-mono text-xs break-all">{skill.path}</p>
                    {skill.body_diff_prior_release_id ? (
                      <p className="text-muted-foreground text-xs">
                        Compared to prior release{" "}
                        <span className="font-mono text-foreground/90">
                          {skill.body_diff_prior_release_id.slice(0, 8)}…
                        </span>
                      </p>
                    ) : null}
                  </div>
                  <pre
                    className="bg-muted/60 max-h-[min(40vh,320px)] overflow-auto rounded-lg border p-3 font-mono text-[0.7rem] leading-snug whitespace-pre-wrap break-words"
                    tabIndex={0}
                  >
                    {skill.body_diff_unified}
                  </pre>
                </section>
              ))}
            </div>
          )}
        </div>
      </DialogContent>
    </Dialog>
  );
}
