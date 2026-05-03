"use client";

import { useEffect, useState, type FormEvent } from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { updateProject } from "@/lib/projects-api";
import type { Project } from "@/lib/types";
import { ApiError, formatApiErrorDetail } from "@/lib/api";
import { toastError, toastSuccess } from "@/lib/toast";

const MAX_LEN = 256;

interface RenameProjectDialogProps {
  project: Project | null;
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

export function RenameProjectDialog({
  project,
  open,
  onOpenChange,
}: RenameProjectDialogProps) {
  const queryClient = useQueryClient();
  const [name, setName] = useState("");

  useEffect(() => {
    if (open && project) setName(project.name);
  }, [open, project?.id, project?.name]);

  const mutation = useMutation({
    mutationFn: (nextName: string) =>
      updateProject(project!.id, { name: nextName }),
    onSuccess: (updated) => {
      queryClient.setQueryData(["project", updated.id], updated);
      queryClient.invalidateQueries({ queryKey: ["projects"] });
      onOpenChange(false);
      toastSuccess("Project Name Updated");
    },
    onError: (err: unknown) => {
      const detail =
        err instanceof ApiError
          ? formatApiErrorDetail(err.body) || err.message
          : String(err);
      toastError(detail || "Could not update project name");
    },
  });

  const handleSubmit = (e: FormEvent) => {
    e.preventDefault();
    if (!project) return;
    const trimmed = name.trim();
    if (!trimmed) {
      toastError("Name is required");
      return;
    }
    if (trimmed.length > MAX_LEN) {
      toastError(`Name must be at most ${MAX_LEN} characters`);
      return;
    }
    if (trimmed === project.name) {
      onOpenChange(false);
      return;
    }
    mutation.mutate(trimmed);
  };

  return (
    <Dialog open={open && project != null} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Rename Project</DialogTitle>
          <DialogDescription>
            Update the display name. The project slug and URLs stay the same.
          </DialogDescription>
        </DialogHeader>
        <form onSubmit={handleSubmit} className="space-y-4">
          <div className="space-y-2">
            <Label htmlFor="rename-project-name">Name</Label>
            <Input
              id="rename-project-name"
              value={name}
              onChange={(e) => setName(e.target.value)}
              maxLength={MAX_LEN}
              disabled={mutation.isPending}
              placeholder={project?.name ?? ""}
            />
          </div>
          <DialogFooter>
            <Button
              type="button"
              variant="outline"
              onClick={() => onOpenChange(false)}
              disabled={mutation.isPending}
            >
              Cancel
            </Button>
            <Button type="submit" disabled={mutation.isPending}>
              Save
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
