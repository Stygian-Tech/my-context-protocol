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
import { MarkdownPreview } from "@/components/dashboard/markdown-preview";
import { cn } from "@/lib/utils";
import { Skeleton } from "@/components/ui/skeleton";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState } from "react";
import { ChevronRightIcon } from "lucide-react";
import type { McpMetadataFieldId, McpMetadataIssue } from "@/lib/mcp-metadata-editor-validation";
import {
  firstIssueForField,
  focusMcpMetadataFieldControl,
  mapApiDetailToMcpField,
  mcpMetadataFieldAnchorId,
  uniqueIssueMessages,
  validateMcpMetadataBeforeSave,
} from "@/lib/mcp-metadata-editor-validation";
import {
  metadataHealthTier,
  type McpMetadataHealthTier,
} from "@/lib/mcp-metadata-health";

/** Muted destructive field chrome — matches releases table “blocking MCP publish” control. */
const FIELD_ERROR_SURFACE =
  "rounded-md border border-destructive/50 bg-destructive/10 p-3";

const INNER_CONTROL_ERROR =
  "!border-destructive/50 bg-destructive/5 dark:bg-destructive/10";

const EXPOSURE_TYPES = ["tool", "resource", "prompt"] as const;
const RISK_LEVELS = ["low", "medium", "high"] as const;
const SKILL_STATUSES = ["ready", "needs_review", "not_publishable"] as const;

/** e.g. `needs_review` → "Needs Review", `tool` → "Tool" */
function selectOptionTitleCase(value: string): string {
  return value
    .split("_")
    .map((word) =>
      word.length === 0 ? "" : word[0]!.toUpperCase() + word.slice(1).toLowerCase()
    )
    .join(" ");
}

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

function FieldErrorHint({
  id,
  message,
}: {
  id: string;
  message: string | undefined;
}) {
  if (!message) return null;
  return (
    <p
      id={id}
      className="text-destructive mb-1 text-xs leading-snug font-medium"
      role="status"
    >
      {message}
    </p>
  );
}

function MetadataHealthGlyph({ tier }: { tier: McpMetadataHealthTier }) {
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

export type ReleaseSkillMetadataInitialFocus = {
  skillId: string;
  field: McpMetadataFieldId;
};

interface ReleaseSkillMetadataDialogProps {
  projectId: string;
  releaseId: string | null;
  open: boolean;
  onOpenChange: (open: boolean) => void;
  /** Open directly on a skill/field (e.g. release row blocking shortcut). */
  initialMcpFocus?: ReleaseSkillMetadataInitialFocus | null;
}

function SkillEditorRow({
  projectId,
  releaseId,
  skill,
  onSaved,
  onCancel,
  scrollToFieldOnOpen,
  onConsumedScrollToField,
}: {
  projectId: string;
  releaseId: string;
  skill: CompiledSkill;
  onSaved?: () => void;
  onCancel?: () => void;
  scrollToFieldOnOpen?: McpMetadataFieldId | null;
  onConsumedScrollToField?: () => void;
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
  /** Errors returned from the API after a failed save (merged with live validation for display). */
  const [serverIssues, setServerIssues] = useState<McpMetadataIssue[]>([]);
  /** When false and body is valid non-empty, show rendered markdown; click or focus opens the editor. */
  const [skillBodyEditing, setSkillBodyEditing] = useState(false);
  const skillBodyTextareaRef = useRef<HTMLTextAreaElement>(null);

  const liveIssues = useMemo(
    () => validateMcpMetadataBeforeSave({ schemaJson, exposure }),
    [schemaJson, exposure]
  );

  const displayIssues = useMemo(() => {
    const byField = new Map<McpMetadataFieldId, McpMetadataIssue>();
    for (const s of serverIssues) {
      byField.set(s.field, s);
    }
    for (const l of liveIssues) {
      byField.set(l.field, l);
    }
    return [...byField.values()];
  }, [liveIssues, serverIssues]);

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
    setServerIssues([]);
    setSkillBodyEditing(false);
  }, [skill]);
  /* eslint-enable react-hooks/set-state-in-effect */

  useLayoutEffect(() => {
    if (!skillBodyEditing) return;
    skillBodyTextareaRef.current?.focus();
  }, [skillBodyEditing]);

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
      setServerIssues([]);
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
      const detail =
        err instanceof ApiError
          ? formatApiErrorDetail(err.body) || err.message
          : "Save failed.";
      const field = mapApiDetailToMcpField(detail);
      setServerIssues([{ field, message: detail }]);
    },
  });

  function clearFieldIssue(field: McpMetadataFieldId) {
    setServerIssues((prev) => prev.filter((i) => i.field !== field));
  }

  function fieldInvalid(field: McpMetadataFieldId): boolean {
    return displayIssues.some((i) => i.field === field);
  }

  const showSkillBodyPreview =
    skillBody.trim().length > 0 &&
    !fieldInvalid("skill_body") &&
    !skillBodyEditing;

  function handleSave() {
    if (liveIssues.length > 0) {
      return;
    }
    setServerIssues([]);
    mutation.mutate();
  }

  const summaryMessages = uniqueIssueMessages(displayIssues);

  const scrollOpenedSkillRef = useRef<string | null>(null);
  useEffect(() => {
    scrollOpenedSkillRef.current = null;
  }, [skill.id]);

  useEffect(() => {
    if (scrollOpenedSkillRef.current === skill.id) return;
    if (liveIssues.length === 0) return;
    scrollOpenedSkillRef.current = skill.id;
    const first = liveIssues.find((i) => i.field !== "_form")?.field;
    if (!first) return;
    const el = document.getElementById(mcpMetadataFieldAnchorId(skill.id, first));
    if (!el) return;
    requestAnimationFrame(() => {
      el.scrollIntoView({ behavior: "smooth", block: "center", inline: "nearest" });
    });
  }, [skill.id, liveIssues]);

  useEffect(() => {
    if (serverIssues.length === 0) return;
    const first = serverIssues.find((i) => i.field !== "_form")?.field;
    if (!first) return;
    const el = document.getElementById(mcpMetadataFieldAnchorId(skill.id, first));
    if (!el) return;
    requestAnimationFrame(() => {
      el.scrollIntoView({ behavior: "smooth", block: "center", inline: "nearest" });
    });
  }, [serverIssues, skill.id]);

  const pendingScrollTokenRef = useRef<string | null>(null);
  useEffect(() => {
    if (!scrollToFieldOnOpen) {
      pendingScrollTokenRef.current = null;
      return;
    }
    const token = `${skill.id}:${scrollToFieldOnOpen}`;
    if (pendingScrollTokenRef.current === token) return;
    pendingScrollTokenRef.current = token;
    const field = scrollToFieldOnOpen;

    if (field === "skill_body") {
      setSkillBodyEditing(true);
    }

    const run = () => {
      const el = document.getElementById(mcpMetadataFieldAnchorId(skill.id, field));
      el?.scrollIntoView({ behavior: "smooth", block: "center", inline: "nearest" });
      if (field === "skill_body") {
        skillBodyTextareaRef.current?.focus({ preventScroll: true });
      } else {
        focusMcpMetadataFieldControl(skill.id, field);
      }
      onConsumedScrollToField?.();
    };

    if (field === "skill_body") {
      setTimeout(run, 0);
    } else {
      requestAnimationFrame(() => {
        requestAnimationFrame(run);
      });
    }
  }, [skill.id, scrollToFieldOnOpen, onConsumedScrollToField]);

  const headerBar = (
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
          disabled={mutation.isPending || liveIssues.length > 0}
        >
          {mutation.isPending ? "Saving…" : "Save"}
        </Button>
      </div>
    </div>
  );

  return (
    <div className="space-y-3 rounded-lg border p-4">
      {headerBar}
      {displayIssues.length > 0 ? (
        <div
          role="alert"
          aria-live="polite"
          className={cn(FIELD_ERROR_SURFACE, "space-y-2 text-sm text-destructive")}
        >
          <p className="font-normal">
            {serverIssues.length > 0
              ? "Couldn't save MCP metadata"
              : "Fix these issues before saving"}
          </p>
          {summaryMessages.length > 0 ? (
            <ul className="list-inside list-disc space-y-1 text-xs leading-relaxed text-destructive/90">
              {summaryMessages.map((msg) => (
                <li key={msg}>{msg}</li>
              ))}
            </ul>
          ) : (
            <p className="text-xs leading-relaxed text-destructive/90">
              Something went wrong. Try again or refresh the page.
            </p>
          )}
        </div>
      ) : null}
      <div className="grid gap-3 lg:grid-cols-3">
        <div
          id={mcpMetadataFieldAnchorId(skill.id, "exposure_type")}
          className={cn("space-y-1.5", fieldInvalid("exposure_type") && FIELD_ERROR_SURFACE)}
        >
          <Label
            className={cn(
              "text-xs",
              fieldInvalid("exposure_type") && "font-semibold text-destructive"
            )}
          >
            MCP exposure
          </Label>
          <FieldErrorHint
            id={`${skill.id}-err-exposure`}
            message={firstIssueForField(displayIssues, "exposure_type")}
          />
          <Select
            value={exposure}
            onValueChange={(v) => {
              clearFieldIssue("exposure_type");
              clearFieldIssue("schema_json");
              setExposure(v ?? "tool");
            }}
          >
            <SelectTrigger
              className="h-9 w-full min-w-0 max-w-full sm:max-w-none"
              aria-invalid={fieldInvalid("exposure_type")}
              aria-describedby={
                firstIssueForField(displayIssues, "exposure_type")
                  ? `${skill.id}-err-exposure`
                  : undefined
              }
            >
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              {EXPOSURE_TYPES.map((v) => (
                <SelectItem key={v} value={v}>
                  {selectOptionTitleCase(v)}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>
        <div
          id={mcpMetadataFieldAnchorId(skill.id, "risk_level")}
          className={cn("space-y-1.5", fieldInvalid("risk_level") && FIELD_ERROR_SURFACE)}
        >
          <Label
            className={cn("text-xs", fieldInvalid("risk_level") && "font-semibold text-destructive")}
          >
            Risk
          </Label>
          <FieldErrorHint
            id={`${skill.id}-err-risk`}
            message={firstIssueForField(displayIssues, "risk_level")}
          />
          <Select
            value={risk}
            onValueChange={(v) => {
              clearFieldIssue("risk_level");
              setRisk(v ?? "low");
            }}
          >
            <SelectTrigger
              className="h-9 w-full min-w-0 max-w-full sm:max-w-none"
              aria-invalid={fieldInvalid("risk_level")}
              aria-describedby={
                firstIssueForField(displayIssues, "risk_level") ? `${skill.id}-err-risk` : undefined
              }
            >
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              {RISK_LEVELS.map((v) => (
                <SelectItem key={v} value={v}>
                  {selectOptionTitleCase(v)}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>
        <div
          id={mcpMetadataFieldAnchorId(skill.id, "status")}
          className={cn("space-y-1.5", fieldInvalid("status") && FIELD_ERROR_SURFACE)}
        >
          <Label
            className={cn("text-xs", fieldInvalid("status") && "font-semibold text-destructive")}
          >
            Publish status
          </Label>
          <FieldErrorHint
            id={`${skill.id}-err-status`}
            message={firstIssueForField(displayIssues, "status")}
          />
          <Select
            value={status}
            onValueChange={(v) => {
              clearFieldIssue("status");
              setStatus(v ?? "ready");
            }}
          >
            <SelectTrigger
              className="h-9 w-full min-w-0 max-w-full sm:max-w-none"
              aria-invalid={fieldInvalid("status")}
              aria-describedby={
                firstIssueForField(displayIssues, "status") ? `${skill.id}-err-status` : undefined
              }
            >
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              {SKILL_STATUSES.map((v) => (
                <SelectItem key={v} value={v}>
                  {selectOptionTitleCase(v)}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>
      </div>
      <div
        className={cn(
          "space-y-3 rounded-md p-3",
          fieldInvalid("use_when") ||
            fieldInvalid("avoid_when") ||
            fieldInvalid("failure_modes") ||
            fieldInvalid("invoke_first")
            ? "border-2 border-destructive bg-destructive/[0.1] ring-1 ring-destructive/30 dark:bg-destructive/[0.14]"
            : "border border-dashed border-border"
        )}
      >
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
          <div
            id={mcpMetadataFieldAnchorId(skill.id, "use_when")}
            className={cn("space-y-1.5", fieldInvalid("use_when") && FIELD_ERROR_SURFACE)}
          >
            <Label
              className={cn("text-xs", fieldInvalid("use_when") && "font-semibold text-destructive")}
            >
              use_when — Read When
            </Label>
            <FieldErrorHint
              id={`${skill.id}-err-use-when`}
              message={firstIssueForField(displayIssues, "use_when")}
            />
            <textarea
              value={useWhenText}
              onChange={(e) => {
                clearFieldIssue("use_when");
                setUseWhenText(e.target.value);
              }}
              rows={4}
              placeholder={"Starting implementation\nPlan mode"}
              aria-invalid={fieldInvalid("use_when")}
              aria-describedby={
                firstIssueForField(displayIssues, "use_when") ? `${skill.id}-err-use-when` : undefined
              }
              className={cn(
                "w-full resize-y rounded-lg border border-input bg-transparent px-2.5 py-2 font-mono text-xs",
                "placeholder:text-muted-foreground focus-visible:border-ring focus-visible:ring-3 focus-visible:ring-ring/50",
                "outline-none dark:bg-input/30",
                fieldInvalid("use_when") && INNER_CONTROL_ERROR
              )}
            />
          </div>
          <div
            id={mcpMetadataFieldAnchorId(skill.id, "avoid_when")}
            className={cn("space-y-1.5", fieldInvalid("avoid_when") && FIELD_ERROR_SURFACE)}
          >
            <Label
              className={cn(
                "text-xs",
                fieldInvalid("avoid_when") && "font-semibold text-destructive"
              )}
            >
              avoid_when — Skip When
            </Label>
            <FieldErrorHint
              id={`${skill.id}-err-avoid-when`}
              message={firstIssueForField(displayIssues, "avoid_when")}
            />
            <textarea
              value={avoidWhenText}
              onChange={(e) => {
                clearFieldIssue("avoid_when");
                setAvoidWhenText(e.target.value);
              }}
              rows={4}
              placeholder={"Pure Q&A\nNo repository access"}
              aria-invalid={fieldInvalid("avoid_when")}
              aria-describedby={
                firstIssueForField(displayIssues, "avoid_when")
                  ? `${skill.id}-err-avoid-when`
                  : undefined
              }
              className={cn(
                "w-full resize-y rounded-lg border border-input bg-transparent px-2.5 py-2 font-mono text-xs",
                "placeholder:text-muted-foreground focus-visible:border-ring focus-visible:ring-3 focus-visible:ring-ring/50",
                "outline-none dark:bg-input/30",
                fieldInvalid("avoid_when") && INNER_CONTROL_ERROR
              )}
            />
          </div>
        </div>
        <div
          id={mcpMetadataFieldAnchorId(skill.id, "failure_modes")}
          className={cn("space-y-1.5", fieldInvalid("failure_modes") && FIELD_ERROR_SURFACE)}
        >
          <Label
            className={cn(
              "text-xs",
              fieldInvalid("failure_modes") && "font-semibold text-destructive"
            )}
          >
            failure_modes — Fallbacks
          </Label>
          <FieldErrorHint
            id={`${skill.id}-err-failure-modes`}
            message={firstIssueForField(displayIssues, "failure_modes")}
          />
          <textarea
            value={failureModesText}
            onChange={(e) => {
              clearFieldIssue("failure_modes");
              setFailureModesText(e.target.value);
            }}
            rows={3}
            placeholder="Issue not linked — document and continue"
            aria-invalid={fieldInvalid("failure_modes")}
            aria-describedby={
              firstIssueForField(displayIssues, "failure_modes")
                ? `${skill.id}-err-failure-modes`
                : undefined
            }
            className={cn(
              "w-full resize-y rounded-lg border border-input bg-transparent px-2.5 py-2 font-mono text-xs",
              "placeholder:text-muted-foreground focus-visible:border-ring focus-visible:ring-3 focus-visible:ring-ring/50",
              "outline-none dark:bg-input/30",
              fieldInvalid("failure_modes") && INNER_CONTROL_ERROR
            )}
          />
        </div>
        <div
          id={mcpMetadataFieldAnchorId(skill.id, "invoke_first")}
          className={cn(
            "flex items-start gap-2 rounded-md",
            fieldInvalid("invoke_first") && FIELD_ERROR_SURFACE
          )}
        >
          <input
            type="checkbox"
            id={`invoke-first-${skill.id}`}
            checked={invokeFirst}
            onChange={(e) => {
              clearFieldIssue("invoke_first");
              setInvokeFirst(e.target.checked);
            }}
            className="border-input text-primary focus-visible:ring-ring mt-0.5 h-4 w-4 rounded border shadow-xs focus-visible:ring-2 focus-visible:outline-none"
          />
          <div className="min-w-0 flex-1">
            <FieldErrorHint
              id={`${skill.id}-err-invoke-first`}
              message={firstIssueForField(displayIssues, "invoke_first")}
            />
            <Label
              htmlFor={`invoke-first-${skill.id}`}
              className={cn(
                "block w-full min-w-0 cursor-pointer text-left text-xs leading-relaxed font-normal",
                fieldInvalid("invoke_first") && "text-destructive"
              )}
            >
              <span className="font-mono font-semibold text-foreground">invoke_first</span>
              <span
                className={cn(
                  "mt-1 block",
                  fieldInvalid("invoke_first") ? "text-destructive/90" : "text-muted-foreground"
                )}
              >
                Ask MCP clients to read this skill before others. Only used when MCP exposure is{" "}
                <span className="font-medium text-foreground">resource</span>. Shown as a hint in{" "}
                <code className="bg-muted/80 rounded px-1 py-px font-mono text-[0.65rem]">
                  resources/list
                </code>
                .
              </span>
            </Label>
          </div>
        </div>
      </div>
      <div
        id={mcpMetadataFieldAnchorId(skill.id, "skill_body")}
        className={cn("space-y-1.5", fieldInvalid("skill_body") && FIELD_ERROR_SURFACE)}
      >
        <Label
          className={cn(
            "text-xs",
            fieldInvalid("skill_body") && "font-semibold text-destructive"
          )}
        >
          Skill Body (Markdown From SKILL.md — MCP Tool/Resource/Prompt Content)
        </Label>
        <FieldErrorHint
          id={`${skill.id}-err-skill-body`}
          message={firstIssueForField(displayIssues, "skill_body")}
        />
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
        {showSkillBodyPreview ? (
          <div
            role="region"
            tabIndex={0}
            aria-label="Skill body (markdown). Press Enter to edit source."
            onClick={(e) => {
              if ((e.target as HTMLElement).closest("a")) return;
              setSkillBodyEditing(true);
            }}
            onKeyDown={(e) => {
              if (e.key === "Enter" || e.key === " ") {
                e.preventDefault();
                setSkillBodyEditing(true);
              }
            }}
            className={cn(
              "max-h-[min(50vh,28rem)] w-full min-h-[140px] cursor-text overflow-y-auto rounded-lg border border-input bg-transparent px-2.5 py-2",
              "outline-none focus-visible:border-ring focus-visible:ring-3 focus-visible:ring-ring/50",
              "dark:bg-input/30",
            )}
          >
            <MarkdownPreview markdown={skillBody} />
            <p className="text-muted-foreground mt-2 border-t border-border/60 pt-2 text-[0.65rem] leading-snug">
              Click outside links or press Enter to edit markdown source.
            </p>
          </div>
        ) : (
          <textarea
            ref={skillBodyTextareaRef}
            value={skillBody}
            onChange={(e) => {
              clearFieldIssue("skill_body");
              setSkillBody(e.target.value);
            }}
            onFocus={() => setSkillBodyEditing(true)}
            onBlur={() => setSkillBodyEditing(false)}
            rows={12}
            aria-invalid={fieldInvalid("skill_body")}
            aria-describedby={
              firstIssueForField(displayIssues, "skill_body") ? `${skill.id}-err-skill-body` : undefined
            }
            className={cn(
              "max-h-[min(50vh,28rem)] w-full min-h-[140px] resize-y rounded-lg border border-input bg-transparent px-2.5 py-2 font-mono text-xs leading-relaxed",
              "placeholder:text-muted-foreground focus-visible:border-ring focus-visible:ring-3 focus-visible:ring-ring/50",
              "outline-none dark:bg-input/30",
              fieldInvalid("skill_body") && INNER_CONTROL_ERROR
            )}
          />
        )}
      </div>
      <div
        id={mcpMetadataFieldAnchorId(skill.id, "summary")}
        className={cn("space-y-1.5", fieldInvalid("summary") && FIELD_ERROR_SURFACE)}
      >
        <Label
          className={cn("text-xs", fieldInvalid("summary") && "font-semibold text-destructive")}
        >
          Summary (MCP metadata blurb)
        </Label>
        <FieldErrorHint
          id={`${skill.id}-err-summary`}
          message={firstIssueForField(displayIssues, "summary")}
        />
        <textarea
          value={summary}
          onChange={(e) => {
            clearFieldIssue("summary");
            setSummary(e.target.value);
          }}
          rows={3}
          aria-invalid={fieldInvalid("summary")}
          aria-describedby={
            firstIssueForField(displayIssues, "summary") ? `${skill.id}-err-summary` : undefined
          }
          className={cn(
            "w-full min-h-[72px] rounded-lg border border-input bg-transparent px-2.5 py-2 text-sm",
            "placeholder:text-muted-foreground focus-visible:border-ring focus-visible:ring-3 focus-visible:ring-ring/50",
            "outline-none dark:bg-input/30",
            fieldInvalid("summary") && INNER_CONTROL_ERROR
          )}
        />
      </div>
      <div
        id={mcpMetadataFieldAnchorId(skill.id, "schema_json")}
        className={cn("space-y-1.5", fieldInvalid("schema_json") && FIELD_ERROR_SURFACE)}
      >
        <div className="flex flex-wrap items-center justify-between gap-2">
          <Label
            className={cn(
              "text-xs font-normal",
              fieldInvalid("schema_json") && "text-destructive"
            )}
          >
            MCP capability JSON (input schema / metadata)
          </Label>
          <Button
            type="button"
            variant="ghost"
            size="sm"
            className="h-7 text-xs"
            onClick={() => {
              clearFieldIssue("schema_json");
              setSchemaDirty(true);
              setSchemaJson("");
            }}
          >
            Reset to defaults
          </Button>
        </div>
        <FieldErrorHint
          id={`${skill.id}-err-schema`}
          message={firstIssueForField(displayIssues, "schema_json")}
        />
        <textarea
          value={schemaJson}
          onChange={(e) => {
            clearFieldIssue("schema_json");
            setSchemaDirty(true);
            setSchemaJson(e.target.value);
          }}
          rows={8}
          spellCheck={false}
          aria-invalid={fieldInvalid("schema_json")}
          aria-describedby={
            firstIssueForField(displayIssues, "schema_json") ? `${skill.id}-err-schema` : undefined
          }
          className={cn(
            "max-h-[min(40vh,22rem)] w-full min-h-[120px] resize-y rounded-lg border border-input bg-transparent px-2.5 py-2 font-mono text-xs",
            "placeholder:text-muted-foreground focus-visible:border-ring focus-visible:ring-3 focus-visible:ring-ring/50",
            "outline-none dark:bg-input/30",
            fieldInvalid("schema_json") && INNER_CONTROL_ERROR
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
  initialMcpFocus = null,
}: ReleaseSkillMetadataDialogProps) {
  const [selectedSkillId, setSelectedSkillId] = useState<string | null>(null);
  const [pendingScrollField, setPendingScrollField] = useState<McpMetadataFieldId | null>(null);
  const appliedInitialFocusKey = useRef<string | null>(null);

  const clearPendingScroll = useCallback(() => {
    setPendingScrollField(null);
  }, []);

  useEffect(() => {
    /* eslint-disable react-hooks/set-state-in-effect -- clear selection when dialog closes */
    if (!open) {
      setSelectedSkillId(null);
      appliedInitialFocusKey.current = null;
      setPendingScrollField(null);
    }
    /* eslint-enable react-hooks/set-state-in-effect */
  }, [open]);

  const { data: skills, isLoading, error } = useQuery({
    queryKey: ["compiled-skills", projectId, releaseId],
    queryFn: () => fetchCompiledSkills(projectId, releaseId!),
    enabled: open && !!releaseId,
  });

  useEffect(() => {
    if (!open || !releaseId || !initialMcpFocus || !skills?.length) return;
    const key = `${releaseId}:${initialMcpFocus.skillId}:${initialMcpFocus.field}`;
    if (appliedInitialFocusKey.current === key) return;
    const s = skills.find((x) => x.id === initialMcpFocus.skillId);
    appliedInitialFocusKey.current = key;
    if (s) {
      setSelectedSkillId(s.id);
      setPendingScrollField(initialMcpFocus.field);
    }
  }, [open, releaseId, initialMcpFocus, skills]);

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
        if (!next) {
          setSelectedSkillId(null);
          setPendingScrollField(null);
          appliedInitialFocusKey.current = null;
        }
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
                scrollToFieldOnOpen={pendingScrollField}
                onConsumedScrollToField={clearPendingScroll}
                onSaved={() => {
                  setSelectedSkillId(null);
                  setPendingScrollField(null);
                }}
                onCancel={() => {
                  setSelectedSkillId(null);
                  setPendingScrollField(null);
                }}
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
