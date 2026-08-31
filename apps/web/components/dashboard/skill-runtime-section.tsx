"use client";

import { useEffect, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { fetchProjectSkillRuntime, updateProjectSkillRuntime } from "@/lib/projects-api";
import type { SkillRuntimeAssignment } from "@/lib/types";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Skeleton } from "@/components/ui/skeleton";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";

function defaultAssignment(): SkillRuntimeAssignment {
  return {
  skill_id: "",
  scope: "workspace",
  activation_mode: "always",
  target_type: "workspace",
  target_id: "",
  required: false,
  priority: 50,
  };
}

export function SkillRuntimeSection({ projectId }: { projectId: string }) {
  const queryClient = useQueryClient();
  const query = useQuery({
    queryKey: ["skill-runtime", projectId],
    queryFn: () => fetchProjectSkillRuntime(projectId),
  });
  const [telemetryEnabled, setTelemetryEnabled] = useState(false);
  const [feedbackEnabled, setFeedbackEnabled] = useState(false);
  const [assignments, setAssignments] = useState<SkillRuntimeAssignment[]>([]);
  const [draft, setDraft] = useState<SkillRuntimeAssignment>(() => defaultAssignment());

  /* eslint-disable react-hooks/set-state-in-effect -- reset editable runtime settings from the fetched server snapshot */
  useEffect(() => {
    if (!query.data) return;
    setTelemetryEnabled(query.data.telemetry_enabled);
    setFeedbackEnabled(query.data.feedback_issue_creation_enabled);
    setAssignments(query.data.assignments);
  }, [query.data]);
  /* eslint-enable react-hooks/set-state-in-effect */

  const save = useMutation({
    mutationFn: () => updateProjectSkillRuntime(projectId, {
      telemetry_enabled: telemetryEnabled,
      telemetry_retention_days: 30,
      semantic_enabled: false,
      feedback_issue_creation_enabled: feedbackEnabled,
      assignments,
    }),
    onSuccess: (value) => queryClient.setQueryData(["skill-runtime", projectId], value),
  });

  if (query.isLoading) return <Skeleton className="h-80 w-full" />;
  if (query.error || !query.data) return <p className="text-destructive text-sm">Could not load the portable skill runtime.</p>;

  return (
    <div className="space-y-5 rounded-lg border p-4">
      <div>
        <h3 className="font-medium">Portable Skill Runtime</h3>
        <p className="text-muted-foreground mt-1 text-sm">
          Configure deterministic activation, feedback draft authorization, and privacy-conscious traces.
        </p>
      </div>

      <div className="grid gap-4 md:grid-cols-2">
        <RuntimeCheckbox label="30-Day Telemetry" description="Opt-in redacted resolution events; prompts, skill bodies, code, and credentials are not stored." checked={telemetryEnabled} onChange={setTelemetryEnabled} />
        <RuntimeCheckbox label="Feedback Issue Drafts" description="Allows explicit feedback calls to prepare an external issue draft; it does not claim the issue was created." checked={feedbackEnabled} onChange={setFeedbackEnabled} />
      </div>

      <div className="space-y-3 border-t pt-4">
        <div><h4 className="text-sm font-medium">Scoped Assignments</h4><p className="text-muted-foreground text-xs">Explicit assignments take precedence over inferred matches.</p></div>
        {assignments.map((assignment, index) => (
          <div key={`${assignment.skill_id}-${assignment.scope}-${assignment.target_type}-${assignment.target_id}-${index}`} className="flex flex-wrap items-center gap-2 rounded-md border px-3 py-2 text-sm">
            <code className="mr-auto">{assignment.skill_id}</code><span>{assignment.scope}</span><span>{assignment.activation_mode}</span><span>{assignment.target_type}: {assignment.target_id}</span><span>{assignment.required ? "Required" : "Advisory"}</span><span>Priority {assignment.priority}</span>
            <Button type="button" size="sm" variant="ghost" onClick={() => setAssignments((rows) => rows.filter((_, rowIndex) => rowIndex !== index))}>Remove</Button>
          </div>
        ))}
        <div className="grid gap-2 md:grid-cols-2 xl:grid-cols-[1fr_9rem_9rem_9rem_1fr_7rem_auto_auto]">
          <Input aria-label="Skill ID" value={draft.skill_id} onChange={(event) => setDraft((value) => ({ ...value, skill_id: event.target.value }))} placeholder="skill-id" />
          <Select value={draft.scope} onValueChange={(scope) => setDraft((value) => ({ ...value, scope: scope as SkillRuntimeAssignment["scope"], target_type: scope as SkillRuntimeAssignment["target_type"], target_id: scope === "global" ? "*" : "" }))}><SelectTrigger aria-label="Assignment scope"><SelectValue /></SelectTrigger><SelectContent>{["global", "organization", "workspace", "repository", "task"].map((scope) => <SelectItem key={scope} value={scope}>{scope}</SelectItem>)}</SelectContent></Select>
          <Select value={draft.activation_mode} onValueChange={(activation_mode) => setDraft((value) => ({ ...value, activation_mode: activation_mode as SkillRuntimeAssignment["activation_mode"] }))}><SelectTrigger><SelectValue /></SelectTrigger><SelectContent>{["always", "intent", "event", "explicit"].map((mode) => <SelectItem key={mode} value={mode}>{mode}</SelectItem>)}</SelectContent></Select>
          <span className="flex items-center rounded-md border px-3 text-sm" aria-label="Assignment target type">{draft.target_type}</span>
          <Input aria-label="Assignment target ID" value={draft.target_id} onChange={(event) => setDraft((value) => ({ ...value, target_id: event.target.value }))} placeholder="Exact target identity" />
          <Input aria-label="Priority" type="number" min={0} max={100} value={draft.priority} onChange={(event) => setDraft((value) => ({ ...value, priority: Number(event.target.value) }))} />
          <label className="flex items-center gap-2 px-2 text-sm"><input type="checkbox" checked={draft.required} onChange={(event) => setDraft((value) => ({ ...value, required: event.target.checked }))} />Required</label>
          <Button type="button" variant="outline" disabled={!draft.skill_id.trim() || !draft.target_id.trim()} onClick={() => { setAssignments((rows) => [...rows, { ...draft, skill_id: draft.skill_id.trim(), target_id: draft.target_id.trim() }]); setDraft(defaultAssignment()); }}>Add</Button>
        </div>
      </div>

      <div className="flex items-center gap-3"><Button type="button" onClick={() => save.mutate()} disabled={save.isPending}>{save.isPending ? "Saving…" : "Save Runtime"}</Button>{save.error ? <p className="text-destructive text-xs">Could not save runtime settings.</p> : null}</div>

      <div className="space-y-2 border-t pt-4">
        <h4 className="text-sm font-medium">Recent Resolution Events</h4>
        {query.data.recent_events.length === 0 ? <p className="text-muted-foreground text-xs">No opted-in runtime events have been recorded.</p> : query.data.recent_events.slice(0, 25).map((event) => (
          <div key={event.id ?? `${event.trace_id}-${event.skill_id}`} className="grid gap-1 rounded-md border px-3 py-2 text-xs md:grid-cols-[12rem_1fr_10rem]">
            <code>{event.trace_id}</code><span>{event.event_type}: {event.skill_id ?? "runtime"}</span><span className="text-muted-foreground">{event.reason_code ?? "—"}</span>
          </div>
        ))}
      </div>
    </div>
  );
}

function RuntimeCheckbox({ label, description, checked, onChange }: { label: string; description: string; checked: boolean; onChange: (value: boolean) => void }) {
  const id = `runtime-${label.toLowerCase().replaceAll(" ", "-")}`;
  return <label htmlFor={id} className="flex cursor-pointer items-start gap-3 rounded-md border p-3"><input id={id} type="checkbox" className="mt-1" checked={checked} onChange={(event) => onChange(event.target.checked)} /><span><span className="block text-sm font-medium">{label}</span><span className="text-muted-foreground block text-xs leading-relaxed">{description}</span></span></label>;
}
