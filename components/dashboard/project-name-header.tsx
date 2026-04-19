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
  const queryClient = useQueryClient();
  const [editing, setEditing] = useState(false);
  const [draft, setDraft] = useState(project.name);

  useEffect(() => {
    if (!editing) setDraft(project.name);
  }, [project.name, editing]);

  useEffect(() => {
    if (!editing) return;
    const el = document.getElementById("project-name-input");
    if (el instanceof HTMLInputElement) {
      el.focus();
      el.select();
    }
  }, [editing]);

  useEffect(() => {
    if (!editing) return;
    const onKeyDown = (e: globalThis.KeyboardEvent) => {
      if (e.key === "Escape") {
        e.preventDefault();
        setDraft(project.name);
        setEditing(false);
      }
    };
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [editing, project.name]);

  const mutation = useMutation({
    mutationFn: (name: string) => updateProject(projectId, { name }),
    onSuccess: (updated) => {
      queryClient.setQueryData(["project", projectId], updated);
      queryClient.invalidateQueries({ queryKey: ["projects"] });
      setEditing(false);
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

  const startEdit = () => {
    setDraft(project.name);
    setEditing(true);
  };

  const cancel = () => {
    setDraft(project.name);
    setEditing(false);
  };

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
      setEditing(false);
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

  if (editing) {
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
            onClick={cancel}
          >
            <XIcon className="mr-1 size-4" aria-hidden />
            Cancel
          </Button>
        </div>
      </form>
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
        onClick={startEdit}
        aria-label="Edit Project Name"
      >
        <PencilIcon className="size-4" aria-hidden />
        <span className="hidden sm:inline">Edit</span>
      </Button>
    </div>
  );
}
