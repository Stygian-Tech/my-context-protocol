"use client";

import { useQuery } from "@tanstack/react-query";
import Link from "next/link";
import { useMemo, useState } from "react";
import {
  Area,
  AreaChart,
  Bar,
  BarChart,
  CartesianGrid,
  ComposedChart,
  Legend,
  Line,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";
import {
  fetchAccountDashboardTimeseries,
  fetchProjectDashboardTimeseries,
} from "@/lib/projects-api";
import {
  DASHBOARD_TIMESERIES_OPTIONS,
  type DashboardTimeseriesRange,
} from "@/lib/dashboard-timeseries";
import { ApiError, formatApiErrorDetail } from "@/lib/api";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { useAuth } from "@/contexts/auth-context";

const axisMuted = "hsl(240 3.8% 46.1%)";
const gridStroke = "hsl(240 5.9% 90% / 0.35)";
const areaFill = "hsl(221 83% 53% / 0.25)";
const areaStroke = "hsl(221 83% 53%)";
const okFill = "hsl(142 71% 45% / 0.85)";
const errFill = "hsl(0 84% 60% / 0.55)";
const latencyStroke = "hsl(262 83% 58%)";

type Variant = "account" | "project";

export function MetricsTimeseriesCharts({
  variant,
  projectId,
}: {
  variant: Variant;
  projectId?: string;
}) {
  const { user } = useAuth();
  const isPro = user?.plan === "pro";
  const [range, setRange] = useState<DashboardTimeseriesRange>("24h");

  const query = useQuery({
    queryKey:
      variant === "account"
        ? ["account-dashboard-timeseries", range]
        : ["project-dashboard-timeseries", projectId, range],
    queryFn: () =>
      variant === "account"
        ? fetchAccountDashboardTimeseries(range)
        : fetchProjectDashboardTimeseries(projectId!, range),
    enabled: variant === "account" || !!projectId,
  });

  const chartRows = useMemo(() => {
    const buckets = query.data?.buckets ?? [];
    return buckets.map((b) => {
      const fail = Math.max(0, b.request_count - b.success_count);
      const successPct =
        b.request_count > 0
          ? Math.round((1000 * b.success_count) / b.request_count) / 10
          : null;
      return {
        label: b.label,
        requests: b.request_count,
        ok: b.success_count,
        err: fail,
        successPct,
        latency: b.avg_latency_ms != null ? Math.round(b.avg_latency_ms) : null,
      };
    });
  }, [query.data?.buckets]);

  const upgradeHint =
    !isPro && (
      <p className="text-muted-foreground mt-2 text-xs">
        Longer history (beyond 7 days) is available on{" "}
        <Link href="/billing" className="text-primary underline-offset-4 hover:underline">
          Pro
        </Link>
        .
      </p>
    );

  if (query.isLoading) {
    return (
      <div className="rounded-lg border p-4">
        <div className="text-muted-foreground text-sm">Loading charts…</div>
      </div>
    );
  }

  if (query.error) {
    const err = query.error;
    if (err instanceof ApiError && err.status === 402) {
      return (
        <div className="rounded-lg border border-amber-500/30 bg-amber-500/5 p-4 text-sm">
          <p className="font-medium text-amber-700 dark:text-amber-400">
            This time range requires Pro.
          </p>
          <p className="text-muted-foreground mt-1 text-xs">
            Upgrade to unlock ranges longer than 7 days.
          </p>
          <Link
            href="/billing"
            className="mt-2 inline-block text-sm font-medium text-primary underline-offset-4 hover:underline"
          >
            View plans
          </Link>
        </div>
      );
    }
    return (
      <div className="rounded-lg border border-destructive/40 bg-destructive/5 p-4 text-sm">
        <p className="font-medium text-destructive">Could not load time series.</p>
        {err instanceof ApiError ? (
          <pre className="text-muted-foreground mt-2 max-h-32 overflow-auto whitespace-pre-wrap text-xs">
            {formatApiErrorDetail(err.body) || err.message}
          </pre>
        ) : (
          <p className="text-muted-foreground mt-2 text-xs">{String(err)}</p>
        )}
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <h3 className="font-medium">Traffic over time</h3>
        <Select
          value={range}
          onValueChange={(v) => v && setRange(v as DashboardTimeseriesRange)}
        >
          <SelectTrigger className="h-9 w-[200px]" size="sm">
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            {DASHBOARD_TIMESERIES_OPTIONS.map((opt) => (
              <SelectItem
                key={opt.value}
                value={opt.value}
                disabled={opt.proOnly && !isPro}
              >
                {opt.label}
                {opt.proOnly ? " (Pro)" : ""}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
      </div>
      {upgradeHint}

      <div className="grid gap-6 lg:grid-cols-2">
        <div className="rounded-lg border p-3 pt-4">
          <p className="text-muted-foreground mb-2 text-xs font-medium tracking-wide uppercase">
            Request volume
          </p>
          <div className="h-[240px] w-full min-w-0">
            <ResponsiveContainer width="100%" height="100%">
              <AreaChart data={chartRows} margin={{ top: 8, right: 8, left: 0, bottom: 4 }}>
                <CartesianGrid stroke={gridStroke} strokeDasharray="3 3" vertical={false} />
                <XAxis
                  dataKey="label"
                  tick={{ fill: axisMuted, fontSize: 10 }}
                  interval="preserveStartEnd"
                  tickMargin={6}
                />
                <YAxis
                  tick={{ fill: axisMuted, fontSize: 10 }}
                  width={40}
                  allowDecimals={false}
                />
                <Tooltip
                  contentStyle={{
                    background: "hsl(0 0% 10%)",
                    border: "1px solid hsl(240 5% 26%)",
                    borderRadius: 8,
                    fontSize: 12,
                  }}
                  labelStyle={{ color: "hsl(0 0% 98%)" }}
                />
                <Area
                  type="monotone"
                  dataKey="requests"
                  name="Requests"
                  stroke={areaStroke}
                  fill={areaFill}
                  strokeWidth={2}
                />
              </AreaChart>
            </ResponsiveContainer>
          </div>
        </div>

        <div className="rounded-lg border p-3 pt-4">
          <p className="text-muted-foreground mb-2 text-xs font-medium tracking-wide uppercase">
            Success vs errors (per bucket)
          </p>
          <div className="h-[240px] w-full min-w-0">
            <ResponsiveContainer width="100%" height="100%">
              <BarChart data={chartRows} margin={{ top: 8, right: 8, left: 0, bottom: 4 }}>
                <CartesianGrid stroke={gridStroke} strokeDasharray="3 3" vertical={false} />
                <XAxis
                  dataKey="label"
                  tick={{ fill: axisMuted, fontSize: 10 }}
                  interval="preserveStartEnd"
                  tickMargin={6}
                />
                <YAxis tick={{ fill: axisMuted, fontSize: 10 }} width={40} allowDecimals={false} />
                <Tooltip
                  contentStyle={{
                    background: "hsl(0 0% 10%)",
                    border: "1px solid hsl(240 5% 26%)",
                    borderRadius: 8,
                    fontSize: 12,
                  }}
                />
                <Legend wrapperStyle={{ fontSize: 12 }} />
                <Bar dataKey="ok" name="2xx–3xx" stackId="s" fill={okFill} />
                <Bar dataKey="err" name="Other" stackId="s" fill={errFill} />
              </BarChart>
            </ResponsiveContainer>
          </div>
        </div>
      </div>

      <div className="rounded-lg border p-3 pt-4">
        <p className="text-muted-foreground mb-2 text-xs font-medium tracking-wide uppercase">
          Success rate &amp; avg latency
        </p>
        <div className="h-[260px] w-full min-w-0">
          <ResponsiveContainer width="100%" height="100%">
            <ComposedChart data={chartRows} margin={{ top: 8, right: 16, left: 0, bottom: 4 }}>
              <CartesianGrid stroke={gridStroke} strokeDasharray="3 3" vertical={false} />
              <XAxis
                dataKey="label"
                tick={{ fill: axisMuted, fontSize: 10 }}
                interval="preserveStartEnd"
                tickMargin={6}
              />
              <YAxis
                yAxisId="left"
                domain={[0, 100]}
                tick={{ fill: axisMuted, fontSize: 10 }}
                width={36}
                label={{ value: "% ok", angle: -90, position: "insideLeft", fill: axisMuted, fontSize: 10 }}
              />
              <YAxis
                yAxisId="right"
                orientation="right"
                tick={{ fill: axisMuted, fontSize: 10 }}
                width={44}
                label={{
                  value: "ms",
                  angle: 90,
                  position: "insideRight",
                  fill: axisMuted,
                  fontSize: 10,
                }}
              />
              <Tooltip
                contentStyle={{
                  background: "hsl(0 0% 10%)",
                  border: "1px solid hsl(240 5% 26%)",
                  borderRadius: 8,
                  fontSize: 12,
                }}
              />
              <Legend wrapperStyle={{ fontSize: 12 }} />
              <Line
                yAxisId="left"
                type="monotone"
                dataKey="successPct"
                name="Success %"
                stroke={okFill}
                dot={false}
                strokeWidth={2}
                connectNulls
              />
              <Line
                yAxisId="right"
                type="monotone"
                dataKey="latency"
                name="Avg latency"
                stroke={latencyStroke}
                dot={false}
                strokeWidth={2}
                connectNulls
              />
            </ComposedChart>
          </ResponsiveContainer>
        </div>
      </div>
    </div>
  );
}
