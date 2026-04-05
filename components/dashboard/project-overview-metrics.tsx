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
import type { ProjectDashboardSummary } from "@/lib/types";

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

function ProjectMetricCards({
  data,
  successHint,
}: {
  data: ProjectDashboardSummary;
  successHint: string;
}) {
  return (
    <>
      <DashboardStatCard
        title="Total MCP requests"
        value={data.total_requests.toLocaleString()}
      />
      <DashboardStatCard
        title="Last 24 hours"
        value={data.requests_last_24h.toLocaleString()}
      />
      <DashboardStatCard
        title="Last 7 days"
        value={data.requests_last_7d.toLocaleString()}
      />
      <DashboardStatCard
        title="Success rate (7d)"
        value={formatPct(data.success_rate_last_7d)}
        hint={successHint}
      />
      <DashboardStatCard
        title="Avg latency (7d)"
        value={
          data.avg_latency_ms_last_7d != null
            ? `${Math.round(data.avg_latency_ms_last_7d)} ms`
            : "—"
        }
      />
      <DashboardStatCard
        title="p95 latency (7d)"
        value={
          data.p95_latency_ms_last_7d != null
            ? `${data.p95_latency_ms_last_7d} ms`
            : "—"
        }
      />
    </>
  );
}

export function ProjectOverviewMetrics({ projectId }: { projectId: string }) {
  const { data, isLoading, error } = useQuery({
    queryKey: ["project-dashboard-summary", projectId],
    queryFn: () => fetchProjectDashboardSummary(projectId),
    enabled: !!projectId,
  });

  if (isLoading) {
    return (
      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        {Array.from({ length: 6 }).map((_, i) => (
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

  const hasMethodBreakdown = data.method_breakdown_last_7d.length > 0;

  const logWord = pluralEn(data.metrics_sample_size_last_7d, "log", "logs");
  const successHint =
    data.requests_last_7d > data.metrics_sample_size_last_7d
      ? `Based on newest ${data.metrics_sample_size_last_7d.toLocaleString()} ${logWord} in the last 7 days.`
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
      {hasMethodBreakdown ? (
        <div className="min-w-0 overflow-hidden rounded-lg border border-border bg-card/50 shadow-xs lg:grid lg:grid-cols-2 lg:items-stretch">
          <div className="flex min-h-0 min-w-0 flex-col border-b border-border p-4 lg:border-b-0 lg:border-r lg:border-border">
            <div className="grid grid-cols-2 gap-4">
              <ProjectMetricCards data={data} successHint={successHint} />
            </div>
          </div>
          <div className="flex min-h-0 min-w-0 flex-col">
            <div className="shrink-0 border-b border-border px-4 py-3">
              <h3 className="font-medium">MCP methods (7d sample)</h3>
            </div>
            <div className="min-h-0 flex-1 overflow-y-auto overflow-x-hidden px-4 pb-4 pt-2">
              <Table>
                <TableHeader className="bg-card sticky top-0 z-[1]">
                  <TableRow className="border-0 hover:bg-transparent">
                    <TableHead className="h-9 bg-card text-xs">Method</TableHead>
                    <TableHead className="h-9 w-24 bg-card text-right text-xs">
                      Count
                    </TableHead>
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
        </div>
      ) : (
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          <ProjectMetricCards data={data} successHint={successHint} />
        </div>
      )}

      <MetricsTimeseriesCharts variant="project" projectId={projectId} />
    </div>
  );
}
