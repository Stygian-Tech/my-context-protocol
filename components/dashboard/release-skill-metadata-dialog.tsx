"use client";

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import {
  fetchCompiledSkills,
  fetchReleaseValidation,
  updateCompiledSkill,
} from "@/lib/projects-api";
import { ApiError, formatApiErrorDetail } from "@/lib/api";
import type { CompiledSkill } from "@/lib/types";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Label } from "@/components/ui/label";
import { cn } from "@/lib/utils";
import { Skeleton } from "@/components/ui/skeleton";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { useEffect, useState } from "react";
import { ChevronRightIcon } from "lucide-react";

const EXPOSURE_TYPES = ["tool", "resource", "prompt"] as const;
const RISK_LEVELS = ["low", "medium", "high"] as const;
const SKILL_STATUSES = ["ready", "needs_review", "not_publishable"] as const;

function formatSchemaEditor(raw: string) {
  const t = raw.trim();
  if (!t) return "";
  try {
    return JSON.stringify(JSON.parse(t), null, 2);
  } catch {
    return raw;
  }
}

/** One entry per non-empty line (matches SKILL comma-lists after split). */
function listFromMultiline(text: string): string[] {
  return text
    .split("\n")
    .map((s) => s.trim())
    .filter((s) => s.length > 0);
}

function multilineFromList(items: string[] | null | undefined): string {
  return (items ?? []).join("\n");
}

type MetadataHealthTier = "red" | "yellow" | "green";

/** Traffic-light heuristic for MCP metadata quality (dashboard only). */
function metadataHealthTier(skill: CompiledSkill): MetadataHealthTier {
  if (skill.status === "not_publishable") return "red";
  const raw = skill.schema_json?.trim() ?? "";
  if (raw) {
    try {
      JSON.parse(raw);
    } catch {
      return "red";
    }
  }
  if (skill.exposure_type === "resource") {
    if (!raw) return "red";
    try {
      const o = JSON.parse(raw) as { uri?: string };
      if (!o.uri?.trim()) return "red";
    } catch {
      return "red";
    }
  }
  if (skill.status === "needs_review") return "yellow";
  if (skill.yaml_frontmatter_present === false) return "yellow";
  if (!skill.skill_body?.trim()) return "yellow";
  if (skill.exposure_type === "resource") {
    const hasRouting =
      (skill.use_when?.length ?? 0) > 0 ||
      (skill.avoid_when?.length ?? 0) > 0 ||
      (skill.failure_modes?.length ?? 0) > 0;
    if (!hasRouting) return "yellow";
  }
  if (skill.status === "ready") return "green";
  return "yellow";
}

function MetadataHealthGlyph({ tier }: { tier: MetadataHealthTier }) {
  const title =
    tier === "green"
      ? "Looks good for publish"
      : tier === "yellow"
        ? "Review suggested"
        : "Blocking issue";
  const cls =
    tier === "green"
      ? "bg-emerald-500"
      : tier === "yellow"
        ? "bg-amber-500"
        : "bg-red-600";
  return (
    <span
      title={title}
      aria-label={title}
      className={cn("inline-block size-2.5 shrink-0 rounded-full ring-2 ring-background", cls)}
    />
  );
}

interface ReleaseSkillMetadataDialogProps {
  projectId: string;
  releaseId: string | null;
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

function SkillEditorRow({
  projectId,
  releaseId,
  skill,
  onSaved,
  onCancel,
}: {
  projectId: string;
  releaseId: string;
  skill: CompiledSkill;
  onSaved?: () => void;
  onCancel?: () => void;
}) {
  const queryClient = useQueryClient();
  const [exposure, setExposure] = useState(skill.exposure_type);
  const [risk, setRisk] = useState(skill.risk_level);
  const [status, setStatus] = useState(skill.status);
  const [summary, setSummary] = useState(skill.summary ?? "");
  const [skillBody, setSkillBody] = useState(skill.skill_body ?? "");
  const [schemaJson, setSchemaJson] = useState(() =>
    formatSchemaEditor(skill.schema_json ?? "")
  );
  const [schemaDirty, setSchemaDirty] = useState(false);
  const [useWhenText, setUseWhenText] = useState(() =>
    multilineFromList(skill.use_when ?? [])
  );
  const [avoidWhenText, setAvoidWhenText] = useState(() =>
    multilineFromList(skill.avoid_when ?? [])
  );
  const [failureModesText, setFailureModesText] = useState(() =>
    multilineFromList(skill.failure_modes ?? [])
  );
  const [invokeFirst, setInvokeFirst] = useState(() => skill.invoke_first ?? false);
  const [saveError, setSaveError] = useState<string | null>(null);

  // Sync local editors when the server row updates (refetch after save or dialog reopen).
  /* eslint-disable react-hooks/set-state-in-effect -- reset draft state from refreshed `skill` props */
  useEffect(() => {
    setExposure(skill.exposure_type);
    setRisk(skill.risk_level);
    setStatus(skill.status);
    setSummary(skill.summary ?? "");
    setSkillBody(skill.skill_body ?? "");
    setSchemaJson(formatSchemaEditor(skill.schema_json ?? ""));
    setSchemaDirty(false);
    setUseWhenText(multilineFromList(skill.use_when ?? []));
    setAvoidWhenText(multilineFromList(skill.avoid_when ?? []));
    setFailureModesText(multilineFromList(skill.failure_modes ?? []));
    setInvokeFirst(skill.invoke_first ?? false);
    setSaveError(null);
  }, [skill]);
  /* eslint-enable react-hooks/set-state-in-effect */

  const mutation = useMutation({
    mutationFn: () => {
      const payload: Parameters<typeof updateCompiledSkill>[3] = {
        exposure_type: exposure,
        risk_level: risk,
        status,
        summary: summary.trim() || null,
        skill_body: skillBody,
        routing: {
          use_when: listFromMultiline(useWhenText),
          avoid_when: listFromMultiline(avoidWhenText),
          failure_modes: listFromMultiline(failureModesText),
          invoke_first: invokeFirst,
        },
      };
      if (schemaDirty) {
        payload.replace_schema = true;
        payload.schema_json = schemaJson;
      }
      return updateCompiledSkill(projectId, releaseId, skill.id, payload);
    },
    onSuccess: () => {
      setSaveError(null);
      setSchemaDirty(false);
      queryClient.invalidateQueries({
        queryKey: ["compiled-skills", projectId, releaseId],
      });
      queryClient.invalidateQueries({ queryKey: ["project-catalog", projectId] });
      queryClient.invalidateQueries({ queryKey: ["releases", projectId] });
      queryClient.invalidateQueries({ queryKey: ["project-dashboard-summary", projectId] });
      queryClient.invalidateQueries({
        queryKey: ["release-validation", projectId, releaseId],
      });
      onSaved?.();
    },
    onError: (err) => {
      if (err instanceof ApiError) {
        setSaveError(formatApiErrorDetail(err.body) || err.message);
      } else {
        setSaveError("Save failed.");
      }
    },
  });

  function handleSave() {
    if (schemaDirty) {
      const t = schemaJson.trim();
      if (t !== "") {
        try {
          JSON.parse(schemaJson);
        } catch {
          setSaveError("MCP JSON must be valid JSON (or leave empty to reset to defaults).");
          return;
        }
      }
    }
    mutation.mutate();
  }

  return (
    <div className="space-y-3 rounded-lg border p-4">
      <div className="flex flex-wrap items-baseline justify-between gap-2">
        <div>
          <p className="font-medium">{skill.name}</p>
          <p className="text-muted-foreground font-mono text-xs break-all">{skill.path}</p>
        </div>
        <div className="flex flex-wrap items-center gap-2">
          {onCancel ? (
            <Button
              type="button"
              variant="outline"
              size="sm"
              onClick={() => onCancel()}
              disabled={mutation.isPending}
            >
              Cancel
            </Button>
          ) : null}
          <Button
            type="button"
            size="sm"
            onClick={handleSave}
            disabled={mutation.isPending}
          >
            {mutation.isPending ? "Saving…" : "Save"}
          </Button>
        </div>
      </div>
      {saveError ? (
        <p className="text-destructive text-sm">{saveError}</p>
      ) : null}
      <div className="grid gap-3 lg:grid-cols-3">
        <div className="space-y-1.5">
          <Label className="text-xs">MCP exposure</Label>
          <Select value={exposure} onValueChange={(v) => setExposure(v ?? "tool")}>
            <SelectTrigger className="h-9">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              {EXPOSURE_TYPES.map((v) => (
                <SelectItem key={v} value={v}>
                  {v}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>
        <div className="space-y-1.5">
          <Label className="text-xs">Risk</Label>
          <Select value={risk} onValueChange={(v) => setRisk(v ?? "low")}>
            <SelectTrigger className="h-9">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              {RISK_LEVELS.map((v) => (
                <SelectItem key={v} value={v}>
                  {v}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>
        <div className="space-y-1.5">
          <Label className="text-xs">Publish status</Label>
          <Select value={status} onValueChange={(v) => setStatus(v ?? "ready")}>
            <SelectTrigger className="h-9">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              {SKILL_STATUSES.map((v) => (
                <SelectItem key={v} value={v}>
                  {v}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>
      </div>
      <div className="space-y-3 rounded-md border border-dashed p-3">
        <div>
          <p className="text-xs font-medium">SKILL Routing (Front Matter)</p>
          <p className="text-muted-foreground mt-0.5 text-xs leading-snug">
            One phrase per line (same as comma-separated lists in SKILL.md). Shown in MCP{" "}
            <code className="font-mono text-[0.7rem]">resources/list</code> and at the top of{" "}
            <code className="font-mono text-[0.7rem]">resources/read</code> when exposure is{" "}
            <span className="font-medium">resource</span>. Values are stored in the release even
            for tools/prompts so you can switch exposure without losing them.
          </p>
        </div>
        <div className="grid gap-3 md:grid-cols-2">
          <div className="space-y-1.5">
            <Label className="text-xs">use_when — Read When</Label>
            <textarea
              value={useWhenText}
              onChange={(e) => setUseWhenText(e.target.value)}
              rows={4}
              placeholder={"Starting implementation\nPlan mode"}
              className={cn(
                "w-full resize-y rounded-lg border border-input bg-transparent px-2.5 py-2 font-mono text-xs",
                "placeholder:text-muted-foreground focus-visible:border-ring focus-visible:ring-3 focus-visible:ring-ring/50",
                "outline-none dark:bg-input/30"
              )}
            />
          </div>
          <div className="space-y-1.5">
            <Label className="text-xs">avoid_when — Skip When</Label>
            <textarea
              value={avoidWhenText}
              onChange={(e) => setAvoidWhenText(e.target.value)}
              rows={4}
              placeholder={"Pure Q&A\nNo repository access"}
              className={cn(
                "w-full resize-y rounded-lg border border-input bg-transparent px-2.5 py-2 font-mono text-xs",
                "placeholder:text-muted-foreground focus-visible:border-ring focus-visible:ring-3 focus-visible:ring-ring/50",
                "outline-none dark:bg-input/30"
              )}
            />
          </div>
        </div>
        <div className="space-y-1.5">
          <Label className="text-xs">failure_modes — Fallbacks</Label>
          <textarea
            value={failureModesText}
            onChange={(e) => setFailureModesText(e.target.value)}
            rows={3}
            placeholder="Issue not linked — document and continue"
            className={cn(
              "w-full resize-y rounded-lg border border-input bg-transparent px-2.5 py-2 font-mono text-xs",
              "placeholder:text-muted-foreground focus-visible:border-ring focus-visible:ring-3 focus-visible:ring-ring/50",
              "outline-none dark:bg-input/30"
            )}
          />
        </div>
        <div className="flex items-start gap-2">
          <input
            type="checkbox"
            id={`invoke-first-${skill.id}`}
            checked={invokeFirst}
            onChange={(e) => setInvokeFirst(e.target.checked)}
            className="border-input text-primary focus-visible:ring-ring mt-0.5 h-4 w-4 rounded border shadow-xs focus-visible:ring-2 focus-visible:outline-none"
          />
          <Label htmlFor={`invoke-first-${skill.id}`} className="text-xs leading-snug font-normal">
            <span className="font-medium">invoke_first</span> — suggest reading this skill before
            others (MCP routing hint; used when exposure is{" "}
            <span className="font-medium">resource</span>)
          </Label>
        </div>
      </div>
      <div className="space-y-1.5">
        <Label className="text-xs">
          Skill Body (Markdown From SKILL.md — MCP Tool/Resource/Prompt Content)
        </Label>
        {skill.body_diff_unified ? (
          <details className="rounded-lg border bg-muted/40 px-3 py-2">
            <summary className="cursor-pointer text-xs font-medium">
              Body Diff vs. Prior Release
              {skill.body_diff_prior_release_id ? (
                <span className="text-muted-foreground ml-1 font-mono font-normal">
                  ({skill.body_diff_prior_release_id.slice(0, 8)}…)
                </span>
              ) : null}
            </summary>
            <pre className="mt-2 max-h-72 overflow-auto whitespace-pre-wrap break-words border-t border-border/60 pt-2 font-mono text-[0.65rem] leading-snug">
              {skill.body_diff_unified}
            </pre>
          </details>
        ) : null}
        {!skill.skill_body?.trim() ? (
          <p className="text-amber-600/90 dark:text-amber-500/90 text-xs leading-snug">
            Empty in the database for this release. Run <span className="font-medium">Sync</span> again so the
            repo body is ingested, or paste content here and save.
          </p>
        ) : null}
        <textarea
          value={skillBody}
          onChange={(e) => setSkillBody(e.target.value)}
          rows={12}
          className={cn(
            "max-h-[min(50vh,28rem)] w-full min-h-[140px] resize-y rounded-lg border border-input bg-transparent px-2.5 py-2 font-mono text-xs leading-relaxed",
            "placeholder:text-muted-foreground focus-visible:border-ring focus-visible:ring-3 focus-visible:ring-ring/50",
            "outline-none dark:bg-input/30"
          )}
        />
      </div>
      <div className="space-y-1.5">
        <Label className="text-xs">Summary (MCP metadata blurb)</Label>
        <textarea
          value={summary}
          onChange={(e) => setSummary(e.target.value)}
          rows={3}
          className={cn(
            "w-full min-h-[72px] rounded-lg border border-input bg-transparent px-2.5 py-2 text-sm",
            "placeholder:text-muted-foreground focus-visible:border-ring focus-visible:ring-3 focus-visible:ring-ring/50",
            "outline-none dark:bg-input/30"
          )}
        />
      </div>
      <div className="space-y-1.5">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <Label className="text-xs">MCP capability JSON (input schema / metadata)</Label>
          <Button
            type="button"
            variant="ghost"
            size="sm"
            className="h-7 text-xs"
            onClick={() => {
              setSchemaDirty(true);
              setSchemaJson("");
            }}
          >
            Reset to defaults
          </Button>
        </div>
        <textarea
          value={schemaJson}
          onChange={(e) => {
            setSchemaDirty(true);
            setSchemaJson(e.target.value);
          }}
          rows={8}
          spellCheck={false}
          className={cn(
            "max-h-[min(40vh,22rem)] w-full min-h-[120px] resize-y rounded-lg border border-input bg-transparent px-2.5 py-2 font-mono text-xs",
            "placeholder:text-muted-foreground focus-visible:border-ring focus-visible:ring-3 focus-visible:ring-ring/50",
            "outline-none dark:bg-input/30"
          )}
        />
        {schemaDirty ? (
          <p className="text-muted-foreground text-xs">
            You changed this JSON — it will replace the stored MCP schema for this skill. Use &quot;Reset to
            defaults&quot; to let the server rebuild it from summary and exposure.
          </p>
        ) : null}
      </div>
    </div>
  );
}

export function ReleaseSkillMetadataDialog({
  projectId,
  releaseId,
  open,
  onOpenChange,
}: ReleaseSkillMetadataDialogProps) {
  const [selectedSkillId, setSelectedSkillId] = useState<string | null>(null);

  useEffect(() => {
    if (!open) setSelectedSkillId(null);
  }, [open]);

  const { data: skills, isLoading, error } = useQuery({
    queryKey: ["compiled-skills", projectId, releaseId],
    queryFn: () => fetchCompiledSkills(projectId, releaseId!),
    enabled: open && !!releaseId,
  });

  const { data: validationReport } = useQuery({
    queryKey: ["release-validation", projectId, releaseId],
    queryFn: () => fetchReleaseValidation(projectId, releaseId!),
    enabled: open && !!releaseId,
  });

  const selectedSkill =
    selectedSkillId && skills ? skills.find((s) => s.id === selectedSkillId) : undefined;

  const showIngestBanner =
    (validationReport?.warnings?.length ?? 0) > 0 ||
    (skills?.some((s) => s.yaml_frontmatter_present === false) ?? false);

  return (
    <Dialog
      open={open}
      onOpenChange={(next) => {
        if (!next) setSelectedSkillId(null);
        onOpenChange(next);
      }}
    >
      <DialogContent className="flex max-h-[92vh] w-[min(88rem,calc(100vw-1rem))] flex-col gap-4 overflow-hidden p-6">
        <DialogHeader className="shrink-0 space-y-1.5">
          <DialogTitle>
            {selectedSkill ? `Edit: ${selectedSkill.name}` : "MCP Metadata"}
          </DialogTitle>
          <DialogDescription>
            {selectedSkill
              ? "Update exposure, routing lists, body, and MCP JSON for this skill. Save writes this release and returns to the list; Cancel returns without saving."
              : "Pick a skill to edit full MCP metadata. Green, yellow, and red indicate publish readiness at a glance."}
          </DialogDescription>
        </DialogHeader>
        {showIngestBanner ? (
          <div className="shrink-0 rounded-lg border border-amber-500/35 bg-amber-500/10 px-3 py-2 text-sm text-amber-950 dark:text-amber-50">
            <p className="font-medium">Ingest Warnings</p>
            <p className="text-muted-foreground mt-1 text-xs leading-snug dark:text-amber-100/90">
              {(validationReport?.warnings?.length ?? 0) > 0
                ? "This release has validation warnings (for example skills without YAML front matter). Open Release errors for the full report."
                : "At least one skill was synced without YAML front matter (name taken from the folder). Add a --- block in the repo when you can."}
            </p>
          </div>
        ) : null}
        {!releaseId ? (
          <p className="text-muted-foreground text-sm">No release selected.</p>
        ) : isLoading ? (
          <Skeleton className="h-40" />
        ) : error ? (
          <div className="space-y-2 rounded-md border border-destructive/40 bg-destructive/5 p-3 text-sm">
            <p className="font-medium text-destructive">Could not load compiled skills.</p>
            {error instanceof ApiError ? (
              <pre className="text-muted-foreground max-h-40 overflow-auto whitespace-pre-wrap break-all text-xs">
                {formatApiErrorDetail(error.body) || error.message}
              </pre>
            ) : null}
          </div>
        ) : skills && skills.length > 0 ? (
          selectedSkill && releaseId ? (
            <div className="min-h-0 flex-1 overflow-y-auto overscroll-contain pr-1 [-ms-overflow-style:auto] [scrollbar-gutter:stable]">
              <SkillEditorRow
                projectId={projectId}
                releaseId={releaseId}
                skill={selectedSkill}
                onSaved={() => setSelectedSkillId(null)}
                onCancel={() => setSelectedSkillId(null)}
              />
            </div>
          ) : (
            <ul className="min-h-0 flex-1 space-y-2 overflow-y-auto overscroll-contain pr-1 [-ms-overflow-style:auto] [scrollbar-gutter:stable]">
              {skills.map((s) => {
                const tier = metadataHealthTier(s);
                return (
                  <li key={s.id}>
                    <button
                      type="button"
                      onClick={() => setSelectedSkillId(s.id)}
                      className={cn(
                        "flex w-full items-center gap-3 rounded-lg border bg-card px-3 py-3 text-left transition-colors",
                        "hover:bg-muted/60 focus-visible:ring-3 focus-visible:ring-ring/50 focus-visible:outline-none"
                      )}
                    >
                      <MetadataHealthGlyph tier={tier} />
                      <div className="min-w-0 flex-1">
                        <p className="font-medium">{s.name}</p>
                        <p className="text-muted-foreground font-mono text-xs break-all">{s.path}</p>
                        <p className="text-muted-foreground mt-0.5 text-xs capitalize">
                          {s.exposure_type} · {s.status.split("_").join(" ")}
                        </p>
                      </div>
                      <ChevronRightIcon className="text-muted-foreground size-4 shrink-0" aria-hidden />
                    </button>
                  </li>
                );
              })}
            </ul>
          )
        ) : (
          <p className="text-muted-foreground text-sm">No compiled skills for this release.</p>
        )}
      </DialogContent>
    </Dialog>
  );
}
