"use client";

import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { fetchProjects, setActiveProject } from "@/lib/projects-api";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";

interface ProjectSelectionDialogProps {
  open: boolean;
}

export function ProjectSelectionDialog({ open }: ProjectSelectionDialogProps) {
  const queryClient = useQueryClient();
  const [selectedId, setSelectedId] = useState<string | null>(null);

  const { data: projects = [], isLoading } = useQuery({
    queryKey: ["projects"],
    queryFn: fetchProjects,
    enabled: open,
  });

  const mutation = useMutation({
    mutationFn: (projectId: string) => setActiveProject(projectId),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["projects"] });
      queryClient.invalidateQueries({ queryKey: ["user"] });
      queryClient.invalidateQueries({ queryKey: ["auth-me"] });
      setSelectedId(null);
    },
  });

  const handleConfirm = () => {
    if (!selectedId) return;
    mutation.mutate(selectedId);
  };

  return (
    <Dialog open={open}>
      <DialogContent showCloseButton={false} className="max-w-md">
        <DialogHeader>
          <DialogTitle>Select Your Active Project</DialogTitle>
          <DialogDescription>
            Your account has been downgraded to Free. Select one project to keep
            active — the others will be suspended and preserved.
          </DialogDescription>
        </DialogHeader>

        {isLoading ? (
          <p className="text-sm text-muted-foreground py-4">
            Loading projects…
          </p>
        ) : (
          <div className="space-y-2 py-2">
            {projects.map((project) => (
              <button
                key={project.id}
                type="button"
                onClick={() => setSelectedId(project.id)}
                className={[
                  "w-full rounded-lg border px-4 py-3 text-left text-sm transition-colors",
                  selectedId === project.id
                    ? "border-primary bg-primary/5 font-medium"
                    : "border-border hover:border-primary/50 hover:bg-muted/40",
                  project.suspended_at
                    ? "opacity-60"
                    : "",
                ]
                  .filter(Boolean)
                  .join(" ")}
              >
                <span className="font-medium">{project.name}</span>
                <span className="ml-2 text-muted-foreground">
                  {project.subdomain}
                </span>
                {project.suspended_at && (
                  <span className="ml-2 rounded-full bg-muted px-1.5 py-0.5 text-xs text-muted-foreground">
                    suspended
                  </span>
                )}
              </button>
            ))}
          </div>
        )}

        {mutation.isError && (
          <p className="text-sm text-destructive">
            Something went wrong. Please try again.
          </p>
        )}

        <div className="flex justify-end pt-2">
          <Button
            onClick={handleConfirm}
            disabled={!selectedId || mutation.isPending}
          >
            {mutation.isPending ? "Saving…" : "Confirm Selection"}
          </Button>
        </div>
      </DialogContent>
    </Dialog>
  );
}
