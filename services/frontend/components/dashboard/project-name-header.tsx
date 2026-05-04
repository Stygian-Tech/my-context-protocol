"use client";

import {
  useEffect,
  useState,
  type FormEvent,
  type KeyboardEvent,
} from "react";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { updateProject } from "@/lib/projects-api";
import type { Project } from "@/lib/types";
import { ApiError, formatApiErrorDetail } from "@/lib/api";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { CheckIcon, PencilIcon, XIcon } from "lucide-react";
import { toastError, toastSuccess } from "@/lib/toast";

const MAX_LEN = 256;

interface ProjectNameHeaderProps {
  project: Project;
  projectId: string;
}

export function ProjectNameHeader({
  project,
  projectId,
}: ProjectNameHeaderProps) {
  const [editing, setEditing] = useState(false);

  if (editing) {
    // Mounting the editor only when `editing` is true means the editor's local
    // `draft` state is initialized from `project.name` each time editing
    // begins; cancelling unmounts and discards in-progress edits. Replaces the
    // previous useEffect-based prop->state sync.
    return (
      <NameEditor
        project={project}
        projectId={projectId}
        onClose={() => setEditing(false)}
      />
    );
  }

  return (
    <div className="flex min-w-0 flex-wrap items-center gap-1">
      <h1 className="min-w-0 max-w-full break-words text-3xl font-bold tracking-tight">
        {project.name}
      </h1>
      <Button
        type="button"
        variant="ghost"
        size="sm"
        className="shrink-0 gap-1 text-muted-foreground hover:text-foreground"
        onClick={() => setEditing(true)}
        aria-label="Edit Project Name"
      >
        <PencilIcon className="size-4" aria-hidden />
        <span className="hidden sm:inline">Edit</span>
      </Button>
    </div>
  );
}

interface NameEditorProps {
  project: Project;
  projectId: string;
  onClose: () => void;
}

function NameEditor({ project, projectId, onClose }: NameEditorProps) {
  const queryClient = useQueryClient();
  const [draft, setDraft] = useState(project.name);

  // Focus the input on mount.
  useEffect(() => {
    const el = document.getElementById("project-name-input");
    if (el instanceof HTMLInputElement) {
      el.focus();
      el.select();
    }
  }, []);

  // Escape cancels editing.
  useEffect(() => {
    const onKeyDown = (e: globalThis.KeyboardEvent) => {
      if (e.key === "Escape") {
        e.preventDefault();
        onClose();
      }
    };
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [onClose]);

  const mutation = useMutation({
    mutationFn: (name: string) => updateProject(projectId, { name }),
    onSuccess: (updated) => {
      queryClient.setQueryData(["project", projectId], updated);
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

  const save = () => {
    const name = draft.trim();
    if (!name) {
      toastError("Name is required");
      return;
    }
    if (name.length > MAX_LEN) {
      toastError(`Name must be at most ${MAX_LEN} characters`);
      return;
    }
    if (name === project.name) {
      onClose();
      return;
    }
    mutation.mutate(name);
  };

  const onFormSubmit = (e: FormEvent) => {
    e.preventDefault();
    save();
  };

  const onInputKeyDown = (e: KeyboardEvent<HTMLInputElement>) => {
    if (e.key === "Enter") {
      e.preventDefault();
      save();
    }
  };

  return (
    <form
      className="flex min-w-0 flex-wrap items-center gap-2"
      onSubmit={onFormSubmit}
      aria-label="Edit Project Name"
    >
      <div className="min-w-0 flex-1 space-y-1">
        <Label htmlFor="project-name-input" className="sr-only">
          Project Name
        </Label>
        <Input
          id="project-name-input"
          value={draft}
          onChange={(e) => setDraft(e.target.value)}
          onKeyDown={onInputKeyDown}
          maxLength={MAX_LEN}
          className="h-auto min-h-10 py-1.5 text-3xl font-bold tracking-tight md:text-3xl"
          disabled={mutation.isPending}
          aria-invalid={draft.trim().length === 0}
        />
      </div>
      <div className="flex shrink-0 gap-2">
        <Button type="submit" size="sm" disabled={mutation.isPending}>
          <CheckIcon className="mr-1 size-4" aria-hidden />
          Save
        </Button>
        <Button
          type="button"
          variant="outline"
          size="sm"
          disabled={mutation.isPending}
          onClick={onClose}
        >
          <XIcon className="mr-1 size-4" aria-hidden />
          Cancel
        </Button>
      </div>
    </form>
  );
}
