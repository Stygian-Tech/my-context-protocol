"use client";

import { useCallback, useEffect, useState } from "react";
import { useAuth } from "@/contexts/auth-context";
import { DashboardStatCard } from "@/components/dashboard/dashboard-stat-card";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Skeleton } from "@/components/ui/skeleton";
import { ApiError, formatApiErrorDetail } from "@/lib/api";
import {
  adminLookup,
  adminUpdateFlags,
  fetchAdminMetrics,
  type AdminLookupResult,
  type AdminPlatformMetrics,
} from "@/lib/admin-api";
import Link from "next/link";
import { ShieldAlertIcon } from "lucide-react";

type IdKind = "github_login" | "github_id" | "email";

export default function AdminPage() {
  const { user, isLoading } = useAuth();
  const [metrics, setMetrics] = useState<AdminPlatformMetrics | null>(null);
  const [metricsError, setMetricsError] = useState<string | null>(null);
  const [metricsLoading, setMetricsLoading] = useState(false);

  const [idKind, setIdKind] = useState<IdKind>("github_login");
  const [idInput, setIdInput] = useState("");
  const [lookupLoading, setLookupLoading] = useState(false);
  const [lookupError, setLookupError] = useState<string | null>(null);
  const [lookupResult, setLookupResult] = useState<AdminLookupResult | null>(
    null
  );

  const [actionMessage, setActionMessage] = useState<string | null>(null);
  const [actionLoading, setActionLoading] = useState(false);

  const loadMetrics = useCallback(async () => {
    setMetricsLoading(true);
    setMetricsError(null);
    try {
      const m = await fetchAdminMetrics();
      setMetrics(m);
    } catch (e) {
      if (e instanceof ApiError && e.status === 403) {
        setMetricsError("You do not have access to admin metrics.");
      } else {
        setMetricsError(
          e instanceof ApiError ? formatApiErrorDetail(e.body) : "Load failed."
        );
      }
      setMetrics(null);
    } finally {
      setMetricsLoading(false);
    }
  }, []);

  useEffect(() => {
    if (!user?.is_admin) return;
    void loadMetrics();
  }, [user?.is_admin, loadMetrics]);

  const runLookup = async () => {
    setLookupLoading(true);
    setLookupError(null);
    setLookupResult(null);
    setActionMessage(null);
    try {
      const trimmed = idInput.trim();
      if (!trimmed) {
        setLookupError("Enter a value to look up.");
        return;
      }
      let body:
        | { github_login: string }
        | { github_id: string }
        | { email: string };
      if (idKind === "github_login") {
        body = { github_login: trimmed };
      } else if (idKind === "github_id") {
        body = { github_id: trimmed };
      } else {
        body = { email: trimmed.toLowerCase() };
      }
      const res = await adminLookup(body);
      setLookupResult(res);
    } catch (e) {
      if (e instanceof ApiError) {
        if (e.status === 404) {
          setLookupError("No account found for that identifier.");
        } else {
          setLookupError(formatApiErrorDetail(e.body));
        }
      } else {
        setLookupError("Lookup failed.");
      }
    } finally {
      setLookupLoading(false);
    }
  };

  const runFlagUpdate = async (patch: {
    is_admin?: boolean;
    paywall_bypass?: boolean;
  }) => {
    if (!lookupResult) return;
    setActionLoading(true);
    setActionMessage(null);
    try {
      await adminUpdateFlags({
        account_id: lookupResult.account_id,
        ...patch,
      });
      setActionMessage("Saved.");
      const trimmed = idInput.trim();
      let body:
        | { github_login: string }
        | { github_id: string }
        | { email: string };
      if (idKind === "github_login") {
        body = { github_login: trimmed };
      } else if (idKind === "github_id") {
        body = { github_id: trimmed };
      } else {
        body = { email: trimmed.toLowerCase() };
      }
      const res = await adminLookup(body);
      setLookupResult(res);
      await loadMetrics();
    } catch (e) {
      setActionMessage(
        e instanceof ApiError ? formatApiErrorDetail(e.body) : "Update failed."
      );
    } finally {
      setActionLoading(false);
    }
  };

  if (isLoading) {
    return (
      <div className="mx-auto max-w-4xl space-y-6">
        <Skeleton className="h-10 w-64" />
        <Skeleton className="h-40 w-full" />
      </div>
    );
  }

  if (!user?.is_admin) {
    return (
      <div className="mx-auto max-w-lg space-y-4">
        <Card>
          <CardHeader>
            <CardTitle className="flex items-center gap-2">
              <ShieldAlertIcon className="size-5" />
              Not authorized
            </CardTitle>
            <CardDescription>
              Admin tools are restricted to platform administrators.
            </CardDescription>
          </CardHeader>
          <CardContent>
            <Button nativeButton={false} render={<Link href="/" />}>
              Back to overview
            </Button>
          </CardContent>
        </Card>
      </div>
    );
  }

  return (
    <div className="mx-auto max-w-4xl space-y-8">
      <div>
        <h1 className="text-3xl font-bold tracking-tight">Admin</h1>
        <p className="text-muted-foreground mt-1">
          Platform-wide aggregates only. Grant or revoke access for a specific
          account after lookup — no directory of users is exposed.
        </p>
      </div>

      <section className="space-y-3">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <h2 className="text-lg font-semibold">Platform metrics</h2>
          <Button
            type="button"
            variant="outline"
            size="sm"
            onClick={() => void loadMetrics()}
            disabled={metricsLoading}
          >
            {metricsLoading ? "Loading…" : "Refresh"}
          </Button>
        </div>
        {metricsError ? (
          <p className="text-destructive text-sm">{metricsError}</p>
        ) : null}
        <div className="grid gap-3 sm:grid-cols-3">
          <DashboardStatCard
            title="Total users"
            value={
              metrics ? String(metrics.total_users) : metricsLoading ? "—" : "—"
            }
          />
          <DashboardStatCard
            title="Total projects"
            value={
              metrics ? String(metrics.total_projects) : metricsLoading ? "—" : "—"
            }
          />
          <DashboardStatCard
            title="Total MCP calls"
            value={
              metrics
                ? String(metrics.total_mcp_calls)
                : metricsLoading
                  ? "—"
                  : "—"
            }
            hint="Count of rows in request logs (includes parse errors logged as MCP traffic)."
          />
        </div>
      </section>

      <Card>
        <CardHeader>
          <CardTitle>Lookup and update flags</CardTitle>
          <CardDescription>
            Use a single identifier. Response shows only account id and current
            flags (no email or profile).
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="flex flex-col gap-3 sm:flex-row sm:items-end">
            <div className="grid flex-1 gap-2">
              <Label>Identifier type</Label>
              <Select
                value={idKind}
                onValueChange={(v) => {
                  setIdKind(v as IdKind);
                  setLookupResult(null);
                }}
              >
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="github_login">GitHub login</SelectItem>
                  <SelectItem value="github_id">GitHub numeric id</SelectItem>
                  <SelectItem value="email">Email (stored on account)</SelectItem>
                </SelectContent>
              </Select>
            </div>
            <div className="grid min-w-0 flex-[2] gap-2">
              <Label htmlFor="admin-lookup-value">Value</Label>
              <Input
                id="admin-lookup-value"
                value={idInput}
                onChange={(e) => setIdInput(e.target.value)}
                placeholder={
                  idKind === "github_login"
                    ? "octocat"
                    : idKind === "github_id"
                      ? "583231"
                      : "user@example.com"
                }
                autoComplete="off"
              />
            </div>
            <Button
              type="button"
              onClick={() => void runLookup()}
              disabled={lookupLoading}
            >
              {lookupLoading ? "Looking up…" : "Lookup"}
            </Button>
          </div>

          {lookupError ? (
            <p className="text-destructive text-sm">{lookupError}</p>
          ) : null}

          {lookupResult ? (
            <div className="space-y-3 rounded-md border bg-muted/30 p-4">
              <p className="font-mono text-sm">
                <span className="text-muted-foreground">Account id: </span>
                {lookupResult.account_id}
              </p>
              <p className="text-sm">
                Admin:{" "}
                <strong>{lookupResult.is_admin ? "yes" : "no"}</strong>
                {" · "}
                Paywall bypass:{" "}
                <strong>{lookupResult.paywall_bypass ? "yes" : "no"}</strong>
              </p>
              <div className="flex flex-wrap gap-2 pt-1">
                <Button
                  type="button"
                  size="sm"
                  variant="secondary"
                  disabled={actionLoading || lookupResult.is_admin}
                  onClick={() => void runFlagUpdate({ is_admin: true })}
                >
                  Grant admin
                </Button>
                <Button
                  type="button"
                  size="sm"
                  variant="outline"
                  disabled={actionLoading || !lookupResult.is_admin}
                  onClick={() => void runFlagUpdate({ is_admin: false })}
                >
                  Revoke admin
                </Button>
                <Button
                  type="button"
                  size="sm"
                  variant="secondary"
                  disabled={actionLoading || lookupResult.paywall_bypass}
                  onClick={() => void runFlagUpdate({ paywall_bypass: true })}
                >
                  Grant paywall bypass
                </Button>
                <Button
                  type="button"
                  size="sm"
                  variant="outline"
                  disabled={actionLoading || !lookupResult.paywall_bypass}
                  onClick={() => void runFlagUpdate({ paywall_bypass: false })}
                >
                  Revoke paywall bypass
                </Button>
              </div>
              {actionMessage ? (
                <p className="text-muted-foreground text-sm">{actionMessage}</p>
              ) : null}
            </div>
          ) : null}
        </CardContent>
      </Card>
    </div>
  );
}
