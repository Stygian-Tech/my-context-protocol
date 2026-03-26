"use client";

import { useQuery } from "@tanstack/react-query";
import Link from "next/link";
import { fetchAccountDashboardSummary } from "@/lib/projects-api";
import { ApiError, formatApiErrorDetail } from "@/lib/api";
import { Skeleton } from "@/components/ui/skeleton";

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
      <p className="mt-1 font-mono text-2xl font-semibold tabular-nums">{value}</p>
      {hint ? <p className="text-muted-foreground mt-1 text-xs leading-snug">{hint}</p> : null}
    </div>
  );
}

function formatPct(x: number | null | undefined): string {
  if (x == null) return "—";
  return `${Math.round(x * 1000) / 10}%`;
}

export function AccountOverview() {
  const { data, isLoading, error } = useQuery({
    queryKey: ["account-dashboard-summary"],
    queryFn: fetchAccountDashboardSummary,
  });

  if (isLoading) {
    return (
      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        {Array.from({ length: 8 }).map((_, i) => (
          <Skeleton key={i} className="h-24 rounded-lg" />
        ))}
      </div>
    );
  }

  if (error) {
    return (
      <div className="rounded-lg border border-destructive/40 bg-destructive/5 p-4 text-sm">
        <p className="font-medium text-destructive">Could not load dashboard metrics.</p>
        {error instanceof ApiError ? (
          <pre className="text-muted-foreground mt-2 max-h-40 overflow-auto whitespace-pre-wrap break-all text-xs">
            {formatApiErrorDetail(error.body) || error.message}
          </pre>
        ) : (
          <p className="text-muted-foreground mt-2 text-xs">{String(error)}</p>
        )}
      </div>
    );
  }

  if (!data) return null;

  const successHint =
    data.requests_last_7d > data.metrics_sample_size_last_7d
      ? `Based on newest ${data.metrics_sample_size_last_7d.toLocaleString()} logs in the last 7 days.`
      : "Based on MCP request logs (HTTP status < 400 = success).";

  return (
    <div className="space-y-8">
      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <StatCard
          title="Total MCP requests"
          value={data.total_requests.toLocaleString()}
        />
        <StatCard
          title="Last 24 hours"
          value={data.requests_last_24h.toLocaleString()}
        />
        <StatCard
          title="Last 7 days"
          value={data.requests_last_7d.toLocaleString()}
        />
        <StatCard
          title="Success rate (7d)"
          value={formatPct(data.success_rate_last_7d)}
          hint={successHint}
        />
        <StatCard
          title="Avg latency (7d)"
          value={
            data.avg_latency_ms_last_7d != null
              ? `${Math.round(data.avg_latency_ms_last_7d)} ms`
              : "—"
          }
        />
        <StatCard
          title="p95 latency (7d)"
          value={
            data.p95_latency_ms_last_7d != null
              ? `${data.p95_latency_ms_last_7d} ms`
              : "—"
          }
        />
        <StatCard
          title="Projects"
          value={`${data.projects_with_active_release} / ${data.projects_total}`}
          hint="With active release / total"
        />
        <StatCard
          title="Published capabilities"
          value={`${data.active_tools_total + data.active_resources_total + data.active_prompts_total}`}
          hint={`${data.active_tools_total} tools · ${data.active_resources_total} resources · ${data.active_prompts_total} prompts (active releases)`}
        />
      </div>

      <div className="grid gap-6 lg:grid-cols-2">
        <div className="rounded-lg border p-4">
          <h3 className="font-medium">MCP methods (7d sample)</h3>
          <ul className="mt-3 max-h-56 space-y-2 overflow-y-auto text-sm">
            {data.method_breakdown_last_7d.length === 0 ? (
              <li className="text-muted-foreground">No traffic in sample window.</li>
            ) : (
              data.method_breakdown_last_7d.map((row) => (
                <li
                  key={row.method}
                  className="flex items-center justify-between gap-2 font-mono text-xs"
                >
                  <span className="min-w-0 truncate">{row.method}</span>
                  <span className="tabular-nums text-foreground">{row.count}</span>
                </li>
              ))
            )}
          </ul>
        </div>
        <div className="rounded-lg border p-4">
          <h3 className="font-medium">Top projects (7d sample)</h3>
          <ul className="mt-3 max-h-56 space-y-2 overflow-y-auto text-sm">
            {data.top_projects_last_7d.length === 0 ? (
              <li className="text-muted-foreground">No per-project traffic in sample.</li>
            ) : (
              data.top_projects_last_7d.map((row) => (
                <li key={row.project_id} className="flex items-center justify-between gap-2">
                  <Link
                    href={`/projects/${row.project_id}`}
                    className="min-w-0 truncate font-medium text-primary underline-offset-4 hover:underline"
                  >
                    {row.project_name}
                  </Link>
                  <span className="font-mono text-xs tabular-nums">
                    {row.request_count}
                  </span>
                </li>
              ))
            )}
          </ul>
        </div>
      </div>
    </div>
  );
}
