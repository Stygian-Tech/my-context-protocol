"use client";

import { useQuery } from "@tanstack/react-query";
import { fetchProjectDashboardSummary } from "@/lib/projects-api";
import { ApiError, formatApiErrorDetail } from "@/lib/api";
import { Skeleton } from "@/components/ui/skeleton";

function shortSha(sha: string | null | undefined): string {
  if (!sha?.trim()) return "—";
  const t = sha.trim();
  if (t === "pending" || t === "unknown") return t;
  return t.length <= 7 ? t : t.slice(0, 7);
}

function StatCard({
  title,
  value,
  hint,
}: {
  title: string;
  value: string;
  hint?: string;
}) {
  return (
    <div className="rounded-lg border bg-card/50 p-4 shadow-xs">
      <p className="text-muted-foreground text-xs font-medium tracking-wide uppercase">
        {title}
      </p>
      <p className="mt-1 font-mono text-xl font-semibold tabular-nums">{value}</p>
      {hint ? <p className="text-muted-foreground mt-1 text-xs leading-snug">{hint}</p> : null}
    </div>
  );
}

function formatPct(x: number | null | undefined): string {
  if (x == null) return "—";
  return `${Math.round(x * 1000) / 10}%`;
}

export function ProjectOverviewMetrics({ projectId }: { projectId: string }) {
  const { data, isLoading, error } = useQuery({
    queryKey: ["project-dashboard-summary", projectId],
    queryFn: () => fetchProjectDashboardSummary(projectId),
    enabled: !!projectId,
  });

  if (isLoading) {
    return (
      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        {Array.from({ length: 4 }).map((_, i) => (
          <Skeleton key={i} className="h-24 rounded-lg" />
        ))}
      </div>
    );
  }

  if (error) {
    return (
      <div className="rounded-lg border border-destructive/40 bg-destructive/5 p-4 text-sm">
        <p className="font-medium text-destructive">Could not load project metrics.</p>
        {error instanceof ApiError ? (
          <pre className="text-muted-foreground mt-2 max-h-32 overflow-auto whitespace-pre-wrap break-all text-xs">
            {formatApiErrorDetail(error.body) || error.message}
          </pre>
        ) : null}
      </div>
    );
  }

  if (!data) return null;

  const successHint =
    data.requests_last_7d > data.metrics_sample_size_last_7d
      ? `Success rate from newest ${data.metrics_sample_size_last_7d.toLocaleString()} logs (7d).`
      : undefined;

  return (
    <div className="space-y-4">
      <div className="rounded-lg border border-dashed p-3 text-sm">
        <span className="text-muted-foreground">Active release </span>
        {data.active_release_id ? (
          <>
            <span className="font-mono font-medium">{shortSha(data.active_commit_sha)}</span>
            {data.active_release_status ? (
              <span className="text-muted-foreground">
                {" "}
                · <span className="text-foreground">{data.active_release_status}</span>
              </span>
            ) : null}
          </>
        ) : (
          <span className="text-muted-foreground">— none activated</span>
        )}
        <span className="text-muted-foreground">
          {" "}
          · {data.active_tools} tools, {data.active_resources} resources, {data.active_prompts}{" "}
          prompts
        </span>
      </div>
      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <StatCard title="Total requests" value={data.total_requests.toLocaleString()} />
        <StatCard title="Last 24h" value={data.requests_last_24h.toLocaleString()} />
        <StatCard title="Last 7d" value={data.requests_last_7d.toLocaleString()} />
        <StatCard
          title="Success (7d)"
          value={formatPct(data.success_rate_last_7d)}
          hint={successHint}
        />
        <StatCard
          title="Avg latency"
          value={
            data.avg_latency_ms_last_7d != null
              ? `${Math.round(data.avg_latency_ms_last_7d)} ms`
              : "—"
          }
        />
        <StatCard
          title="p95 latency"
          value={
            data.p95_latency_ms_last_7d != null ? `${data.p95_latency_ms_last_7d} ms` : "—"
          }
        />
      </div>
      {data.method_breakdown_last_7d.length > 0 ? (
        <div className="rounded-lg border p-3">
          <p className="text-xs font-medium">Methods (7d sample)</p>
          <ul className="mt-2 flex flex-wrap gap-x-4 gap-y-1 font-mono text-xs">
            {data.method_breakdown_last_7d.map((m) => (
              <li key={m.method}>
                <span className="text-muted-foreground">{m.method}</span>{" "}
                <span className="tabular-nums">{m.count}</span>
              </li>
            ))}
          </ul>
        </div>
      ) : null}
    </div>
  );
}
