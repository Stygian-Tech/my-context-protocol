"use client";

import { useQuery } from "@tanstack/react-query";
import { fetchProjectDashboardSummary } from "@/lib/projects-api";
import { ApiError, formatApiErrorDetail } from "@/lib/api";
import { Skeleton } from "@/components/ui/skeleton";
import { MetricsTimeseriesCharts } from "@/components/dashboard/metrics-timeseries-charts";
import { DashboardStatCard } from "@/components/dashboard/dashboard-stat-card";
import { pluralEn } from "@/lib/pluralize";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";

function shortSha(sha: string | null | undefined): string {
  if (!sha?.trim()) return "—";
  const t = sha.trim();
  if (t === "pending" || t === "unknown") return t;
  return t.length <= 7 ? t : t.slice(0, 7);
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
      <div className="grid gap-4 lg:grid-cols-[minmax(0,1fr)_minmax(0,18rem)]">
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3">
          {Array.from({ length: 6 }).map((_, i) => (
            <Skeleton key={i} className="h-24 rounded-lg" />
          ))}
        </div>
        <Skeleton className="hidden h-full min-h-48 rounded-lg lg:block" />
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

  const logWord = pluralEn(data.metrics_sample_size_last_7d, "log", "logs");
  const successHint =
    data.requests_last_7d > data.metrics_sample_size_last_7d
      ? `Success rate from newest ${data.metrics_sample_size_last_7d.toLocaleString()} ${logWord} (7d).`
      : "Based on MCP request logs: HTTP 2xx/3xx with no logged JSON-RPC error. Failed calls use non-success HTTP status and/or a logged error code.";

  const activeCapsSummary = `${data.active_tools} ${pluralEn(data.active_tools, "tool", "tools")}, ${data.active_resources} ${pluralEn(data.active_resources, "resource", "resources")}, ${data.active_prompts} ${pluralEn(data.active_prompts, "prompt", "prompts")}`;

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
          · {activeCapsSummary}
        </span>
      </div>
      <div
        className={
          data.method_breakdown_last_7d.length > 0
            ? "grid gap-4 lg:grid-cols-[minmax(0,1fr)_minmax(0,18rem)] lg:items-stretch"
            : "contents"
        }
      >
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3">
          <DashboardStatCard
            title="Total requests"
            value={data.total_requests.toLocaleString()}
            valueClassName="text-xl"
          />
          <DashboardStatCard
            title="Last 24h"
            value={data.requests_last_24h.toLocaleString()}
            valueClassName="text-xl"
          />
          <DashboardStatCard
            title="Last 7d"
            value={data.requests_last_7d.toLocaleString()}
            valueClassName="text-xl"
          />
          <DashboardStatCard
            title="Success (7d)"
            value={formatPct(data.success_rate_last_7d)}
            hint={successHint}
            valueClassName="text-xl"
          />
          <DashboardStatCard
            title="Avg latency"
            value={
              data.avg_latency_ms_last_7d != null
                ? `${Math.round(data.avg_latency_ms_last_7d)} ms`
                : "—"
            }
            valueClassName="text-xl"
          />
          <DashboardStatCard
            title="p95 latency"
            value={
              data.p95_latency_ms_last_7d != null ? `${data.p95_latency_ms_last_7d} ms` : "—"
            }
            valueClassName="text-xl"
          />
        </div>
        {data.method_breakdown_last_7d.length > 0 ? (
          <div className="flex min-h-0 min-w-0 flex-col overflow-hidden rounded-lg border bg-card/50 shadow-xs">
            <div className="border-b px-3 py-2.5">
              <p className="text-muted-foreground text-xs font-medium tracking-wide uppercase">
                Methods (7d sample)
              </p>
            </div>
            <div className="min-h-0 flex-1 overflow-auto">
              <Table>
                <TableHeader>
                  <TableRow className="hover:bg-transparent">
                    <TableHead className="h-9 text-xs">Method</TableHead>
                    <TableHead className="h-9 w-24 text-right text-xs">Count</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {data.method_breakdown_last_7d.map((m) => (
                    <TableRow key={m.method}>
                      <TableCell className="max-w-[1px] truncate py-2 font-mono text-xs">
                        <span title={m.method}>{m.method}</span>
                      </TableCell>
                      <TableCell className="py-2 text-right font-mono text-xs tabular-nums">
                        {m.count.toLocaleString()}
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </div>
          </div>
        ) : null}
      </div>

      <MetricsTimeseriesCharts variant="project" projectId={projectId} />
    </div>
  );
}
