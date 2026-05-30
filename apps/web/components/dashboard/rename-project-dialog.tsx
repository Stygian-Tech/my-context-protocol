"use client";

import { useState, type FormEvent } from "react";
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
  return (
    <Dialog open={open && project != null} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Rename Project</DialogTitle>
          <DialogDescription>
            Update the display name. The project slug and URLs stay the same.
          </DialogDescription>
        </DialogHeader>
        {project ? (
          // key={project.id} forces a fresh form (with project.name as initial
          // value) whenever the user opens the dialog for a different project,
          // and Radix unmounts DialogContent when `open` is false so reopening
          // for the same project also resets state — replaces the previous
          // useEffect-based prop->state sync.
          <RenameProjectForm
            key={project.id}
            project={project}
            onClose={() => onOpenChange(false)}
          />
        ) : null}
      </DialogContent>
    </Dialog>
  );
}

interface RenameProjectFormProps {
  project: Project;
  onClose: () => void;
}

function RenameProjectForm({ project, onClose }: RenameProjectFormProps) {
  const queryClient = useQueryClient();
  const [name, setName] = useState(project.name);

  const mutation = useMutation({
    mutationFn: (nextName: string) =>
      updateProject(project.id, { name: nextName }),
    onSuccess: (updated) => {
      queryClient.setQueryData(["project", updated.id], updated);
      queryClient.invalidateQueries({ queryKey: ["projects"] });
      onClose();
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
      onClose();
      return;
    }
    mutation.mutate(trimmed);
  };

  return (
    <form onSubmit={handleSubmit} className="space-y-4">
      <div className="space-y-2">
        <Label htmlFor="rename-project-name">Name</Label>
        <Input
          id="rename-project-name"
          value={name}
          onChange={(e) => setName(e.target.value)}
          maxLength={MAX_LEN}
          disabled={mutation.isPending}
          placeholder={project.name}
        />
      </div>
      <DialogFooter>
        <Button
          type="button"
          variant="outline"
          onClick={onClose}
          disabled={mutation.isPending}
        >
          Cancel
        </Button>
        <Button type="submit" disabled={mutation.isPending}>
          Save
        </Button>
      </DialogFooter>
    </form>
  );
}
