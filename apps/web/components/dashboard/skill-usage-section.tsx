"use client";

import { Fragment, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { pluralEn } from "@/lib/pluralize";
import { fetchProjectSkillUsage } from "@/lib/projects-api";
import type { SkillUsageCounts, SkillUsageReason, SkillUsageSort, SkillUsageWindow } from "@/lib/types";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";

const metrics: { key: keyof SkillUsageCounts; label: string; sort?: SkillUsageSort }[] = [
  { key: "surfaced", label: "Surfaced", sort: "surfaced" },
  { key: "instructions_delivered", label: "Instructions Delivered", sort: "instructions_delivered" },
  { key: "resolver_selected", label: "Resolver Selected" },
  { key: "resolver_suggested", label: "Resolver Suggested" },
  { key: "resolver_excluded", label: "Resolver Excluded" },
  { key: "agent_reported_used", label: "Agent-Reported Used", sort: "agent_reported_used" },
  { key: "agent_reported_skipped", label: "Agent-Reported Skipped", sort: "agent_reported_skipped" },
];
const reasonLabels: Record<string, string> = {
  not_relevant: "Not Relevant", redundant: "Redundant", instruction_conflict: "Instruction Conflict",
  missing_capability: "Missing Capability", task_changed: "Task Changed", other: "Other",
};
const number = new Intl.NumberFormat();
function timestamp(value: string) { return new Date(value).toLocaleString(); }
function legacyOnly(counts: SkillUsageCounts) {
  return counts.legacy_resolver_selected > 0 && counts.supporting_file_read === 0 && metrics.every(({ key }) => counts[key] === 0);
}
function metricValue(count: number, unavailable: boolean) {
  return unavailable ? <span aria-label="Unavailable for legacy activity" title="This measurement was not collected for legacy activity">—</span> : number.format(count);
}

export function SkillUsageSection({ projectId }: { projectId: string }) {
  const [window, setWindow] = useState<SkillUsageWindow>("7d");
  const [page, setPage] = useState(1);
  const [sort, setSort] = useState<SkillUsageSort>("activity");
  const [direction, setDirection] = useState<"asc" | "desc">("desc");
  const [expanded, setExpanded] = useState<string | null>(null);
  const query = useQuery({
    queryKey: ["skill-usage", projectId, { window, page, sort, direction }],
    queryFn: () => fetchProjectSkillUsage(projectId, { window, page, page_size: 25, sort, direction }),
  });
  const data = query.data;
  function changeSort(next: SkillUsageSort) {
    setDirection(sort === next && direction === "desc" ? "asc" : "desc");
    setSort(next); setPage(1); setExpanded(null);
  }
  function sortHeader(label: string, key: SkillUsageSort) {
    return <th scope="col" className="px-3 py-2 text-left" aria-sort={sort === key ? direction === "asc" ? "ascending" : "descending" : "none"}>
      <button type="button" className="rounded-sm text-left underline-offset-4 hover:underline focus-visible:outline-2" onClick={() => changeSort(key)}>{label}{sort === key ? direction === "asc" ? " ↑" : " ↓" : ""}</button>
    </th>;
  }

  return <section aria-labelledby="skill-usage-heading" className="min-w-0 space-y-4 rounded-lg border p-4">
    <div className="flex flex-wrap items-start justify-between gap-3">
      <div className="min-w-0"><h3 id="skill-usage-heading" className="font-medium">Skill Usage</h3>
        <p className="text-muted-foreground mt-1 max-w-3xl text-sm">Observed delivery and resolver activity are separate from agent-reported use. Agent reports provide partial coverage: a missing report is unknown, never a skipped skill.</p>
      </div>
      <label className="flex items-center gap-2 text-sm">Time Window
        <select aria-label="Skill usage time window" className="bg-background rounded-md border px-3 py-2" value={window} onChange={(event) => { setWindow(event.target.value as SkillUsageWindow); setPage(1); setExpanded(null); }}>
          <option value="24h">Last 24 Hours</option><option value="7d">Last 7 Days</option><option value="30d">Last 30 Days</option>
        </select>
      </label>
    </div>
    {query.isLoading ? <div role="status" aria-label="Loading skill usage"><Skeleton className="h-48 w-full" /></div> : null}
    {query.error ? <div role="alert" className="text-destructive flex items-center gap-3 text-sm">Could not load skill usage.<Button size="sm" variant="outline" onClick={() => void query.refetch()}>Retry</Button></div> : null}
    {data && !query.error ? <>
      <div className="text-muted-foreground space-y-1 text-xs">
        <p>{data.collection_enabled ? "Collection enabled." : "Collection disabled. New activity is not recorded; retained history remains visible until it expires."} Retention: {data.retention_days} days.</p>
        <p>Effective window: {timestamp(data.effective_from)} – {timestamp(data.effective_to)}. The requested window is limited by retention.</p>
        <p>Historical measurements before this feature are unavailable except legacy resolver selections. Zero means no recorded activity in this window, not proof that a skill was never used.</p>
      </div>
      {data.skills.length === 0 ? <p className="text-muted-foreground py-5 text-sm">No current skills or retained skill activity in this window.</p> : <div role="region" aria-label="Skill usage table" tabIndex={0} className="overflow-x-auto rounded-md border focus-visible:outline-2">
        <table className="w-full text-sm">
          <caption className="sr-only">Per-skill recorded activity. Expand a skill for versions, supporting file reads, and reported skip reasons.</caption>
          <thead className="bg-muted/40 text-xs"><tr>{sortHeader("Skill", "skill_id")}{metrics.map((metric) => <Fragment key={metric.key}>{metric.sort ? sortHeader(metric.label, metric.sort) : <th scope="col" className="px-3 py-2 text-left">{metric.label}</th>}</Fragment>)}{sortHeader("Last Activity", "activity")}</tr></thead>
          <tbody>{data.skills.map((skill) => <Fragment key={skill.skill_id}>
            <tr className="border-t align-top">
              <td className="min-w-48 max-w-80 px-3 py-3"><button type="button" aria-expanded={expanded === skill.skill_id} aria-controls={`usage-detail-${skill.skill_id}`} className="block w-full rounded-sm text-left font-medium break-words underline-offset-4 hover:underline focus-visible:outline-2" onClick={() => setExpanded(expanded === skill.skill_id ? null : skill.skill_id)}>{expanded === skill.skill_id ? "− " : "+ "}{skill.name || skill.skill_id}</button>
                <code className="text-muted-foreground block break-all text-xs">{skill.skill_id}</code>
                {!skill.is_current ? <span className="text-muted-foreground text-xs">Historical Skill</span> : null}
                {legacyOnly(skill.counts) ? <p className="text-muted-foreground mt-1 text-xs">Legacy Measurements Only</p> : null}
                {!skill.last_activity ? <p className="text-muted-foreground mt-1 text-xs">No recorded activity</p> : null}
              </td>
              {metrics.map((metric) => <td key={metric.key} className="px-3 py-3 tabular-nums">{metricValue(skill.counts[metric.key], legacyOnly(skill.counts))}</td>)}
              <td className="px-3 py-3 text-xs">{skill.last_activity ? timestamp(skill.last_activity) : "—"}</td>
            </tr>
            {expanded === skill.skill_id ? <tr className="border-t"><td colSpan={9} id={`usage-detail-${skill.skill_id}`} className="bg-muted/20 p-4"><SkillUsageDetail projectId={projectId} skillId={skill.skill_id} window={window} /></td></tr> : null}
          </Fragment>)}</tbody>
        </table>
      </div>}
      <div className="flex flex-wrap items-center justify-between gap-3 text-xs">
        <p aria-live="polite">{number.format(data.total)} {pluralEn(data.total, "skill", "skills")} · Page {data.page} of {Math.max(1, Math.ceil(data.total / data.page_size))}</p>
        <div className="flex gap-2"><Button size="sm" variant="outline" disabled={page <= 1} onClick={() => { setPage(page - 1); setExpanded(null); }}>Previous</Button><Button size="sm" variant="outline" disabled={page * data.page_size >= data.total} onClick={() => { setPage(page + 1); setExpanded(null); }}>Next</Button></div>
      </div>
    </> : null}
  </section>;
}

function SkillUsageDetail({ projectId, skillId, window }: { projectId: string; skillId: string; window: SkillUsageWindow }) {
  const query = useQuery({
    queryKey: ["skill-usage", projectId, { window, skill_id: skillId }],
    queryFn: () => fetchProjectSkillUsage(projectId, { window, skill_id: skillId }),
  });
  if (query.isLoading) return <p role="status">Loading skill details…</p>;
  if (query.error) return <div role="alert">Could not load skill details. <Button size="sm" variant="outline" onClick={() => void query.refetch()}>Retry Details</Button></div>;
  const skill = query.data?.skills[0];
  if (!skill) return <p>No retained details for this skill in this window.</p>;
  return <div className="space-y-4 text-xs">
    <div className="flex flex-wrap gap-6"><p>Supporting File Reads: <strong>{number.format(skill.counts.supporting_file_read)}</strong></p><p>Legacy Resolver Selections: <strong>{number.format(skill.counts.legacy_resolver_selected)}</strong> (version unknown)</p></div>
    <p className="text-muted-foreground">Agent-reported skipped means the agent explicitly reported considering and declining this skill. Private deliberation is not observable.</p>
    <div className="grid gap-4 md:grid-cols-2"><Reasons heading="Resolver Exclusion Reasons" reasons={skill.resolver_exclusion_reasons} /><Reasons heading="Agent-Reported Skip Reasons" reasons={skill.agent_skip_reasons} /></div>
    <h4 className="font-medium">Versions and Releases</h4>
    {skill.versions.length === 0 ? <p className="text-muted-foreground">No recorded version activity.</p> : <div className="grid gap-3 xl:grid-cols-2">{skill.versions.map((version, index) => <div key={`${version.release_id}-${version.version}-${version.checksum}-${index}`} className="min-w-0 space-y-2 rounded-md border p-3">
      <dl className="space-y-1 break-all"><div><dt className="inline font-medium">Version: </dt><dd className="inline">{version.version ?? "Unknown (legacy)"}</dd></div><div><dt className="inline font-medium">Release: </dt><dd className="inline font-mono">{version.release_id ?? "Unknown"}</dd></div><div><dt className="inline font-medium">Checksum: </dt><dd className="inline font-mono">{version.checksum ?? "Unavailable"}</dd></div></dl>
      <dl className="grid grid-cols-2 gap-x-4 gap-y-1">{[...metrics, { key: "supporting_file_read" as const, label: "Supporting File Reads" }, { key: "legacy_resolver_selected" as const, label: "Legacy Resolver Selections" }].map((metric) => <div key={metric.key}><dt className="text-muted-foreground">{metric.label}</dt><dd className="tabular-nums">{metricValue(version.counts[metric.key], metric.key !== "legacy_resolver_selected" && !version.version && !version.release_id && legacyOnly(version.counts))}</dd></div>)}</dl>
    </div>)}</div>}
  </div>;
}

function Reasons({ heading, reasons }: { heading: string; reasons: SkillUsageReason[] }) {
  return <div><h4 className="mb-2 font-medium">{heading}</h4>{reasons.length === 0 ? <p className="text-muted-foreground">No recorded reasons.</p> : <dl className="space-y-1">{reasons.map(({ reason, count }) => <div key={reason} className="flex justify-between gap-4"><dt className="break-all">{reasonLabels[reason] ?? reason.replaceAll("_", " ")}</dt><dd className="tabular-nums">{number.format(count)}</dd></div>)}</dl>}</div>;
}
