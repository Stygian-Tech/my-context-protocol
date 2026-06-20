"use client";

import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { RefreshCwIcon } from "lucide-react";
import {
  fetchCustomDomain,
  setProjectCustomDomain,
  verifyProjectCustomDomain,
} from "@/lib/projects-api";
import { ApiError, formatApiErrorDetail } from "@/lib/api";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Skeleton } from "@/components/ui/skeleton";
import { cn } from "@/lib/utils";

/** Matches MCP Catalog / Project Info top-level sections (page background, not bg-card). */
const SECTION_SHELL =
  "space-y-4 rounded-lg border p-4 text-sm text-card-foreground";

/** Matches MCP catalog monospace / URL inset panels. */
const INSET_SURFACE =
  "rounded-lg border border-border/80 bg-muted/35 dark:bg-muted/20";

function certificateStatusLabel(
  status: "not_configured" | "pending" | "issued" | "failed" | "unknown" | null | undefined,
) {
  switch (status) {
    case "issued":
      return "TLS issued";
    case "pending":
      return "TLS pending";
    case "failed":
      return "TLS failed";
    case "not_configured":
      return "TLS not configured";
    case "unknown":
      return "TLS unknown";
    default:
      return null;
  }
}

interface CustomDomainSectionProps {
  projectId: string;
  isPro?: boolean;
}

export function CustomDomainSection({ projectId, isPro = true }: CustomDomainSectionProps) {
  // Hooks must be called unconditionally before any early returns.
  const [hostname, setHostname] = useState("");
  const queryClient = useQueryClient();

  const { data, isLoading } = useQuery({
    queryKey: ["custom-domain", projectId],
    queryFn: () => fetchCustomDomain(projectId),
  });

  const setMutation = useMutation({
    mutationFn: () => setProjectCustomDomain(projectId, hostname.trim()),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["custom-domain", projectId] });
      queryClient.invalidateQueries({ queryKey: ["project", projectId] });
      setHostname("");
    },
  });

  const verifyMutation = useMutation({
    mutationFn: () => verifyProjectCustomDomain(projectId),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["custom-domain", projectId] });
      queryClient.invalidateQueries({ queryKey: ["project", projectId] });
    },
  });

  if (!isPro) {
    return (
      <section className={SECTION_SHELL} aria-labelledby="custom-domain-heading">
        <div className="flex items-start justify-between gap-2">
          <div className="space-y-1">
            <h2
              id="custom-domain-heading"
              className="text-base leading-snug font-medium text-foreground"
            >
              Custom Domain
            </h2>
            <p className="text-sm text-muted-foreground">
              Point your own hostname at this project with automatic TLS. Verified domains stay saved,
              but routing requires active Pro.
            </p>
          </div>
          <span className="shrink-0 rounded-full bg-muted px-2 py-0.5 text-xs font-medium text-muted-foreground">
            Pro
          </span>
        </div>
        <a
          href="/billing"
          className="inline-flex w-fit items-center rounded-md border border-input bg-background px-3 py-1.5 text-xs font-medium shadow-sm hover:bg-accent hover:text-accent-foreground"
        >
          Upgrade to Pro
        </a>
      </section>
    );
  }

  if (isLoading || !data) {
    return <Skeleton className="h-40 w-full" />;
  }

  const tlsLabel = certificateStatusLabel(data.certificate_status);
  const canRefreshChecks =
    Boolean(data.hostname) &&
    (!data.verified ||
      data.certificate_status === "failed" ||
      data.certificate_status === "not_configured" ||
      data.certificate_status === "unknown");
  const verifyError =
    verifyMutation.error instanceof ApiError
      ? formatApiErrorDetail(verifyMutation.error.body) || verifyMutation.error.message
      : verifyMutation.error
        ? "Could not refresh DNS and TLS checks."
        : null;

  return (
    <section
      className={SECTION_SHELL}
      aria-labelledby="custom-domain-heading"
    >
      <div className="space-y-1.5">
        <h2
          id="custom-domain-heading"
          className="text-base leading-snug font-medium text-foreground"
        >
          Custom Domain
        </h2>
        <p className="text-sm text-muted-foreground">
          Point your own hostname at this project. Add the TXT record we show,
          then verify. Routing remains active while the account has Pro.
        </p>
      </div>
      <div className="space-y-4">
        {data.hostname && (
          <div>
            <span className="text-muted-foreground">Hostname: </span>
            <span className="font-medium">{data.hostname}</span>
            {data.verified ? (
              <span className="ml-2 text-green-600 dark:text-green-500">
                Verified
              </span>
            ) : (
              <span className="text-muted-foreground ml-2">
                Pending verification
              </span>
            )}
            {tlsLabel && (
              <span
                className={cn(
                  "ml-2",
                  data.certificate_status === "issued"
                    ? "text-green-600 dark:text-green-500"
                    : data.certificate_status === "failed" || data.certificate_status === "not_configured"
                      ? "text-destructive"
                      : "text-muted-foreground",
                )}
              >
                {tlsLabel}
              </span>
            )}
          </div>
        )}
        {data.instructions && (
          <p
            className={cn(
              INSET_SURFACE,
              "whitespace-pre-wrap p-3 font-mono text-xs break-all",
            )}
          >
            {data.instructions}
          </p>
        )}
        {verifyError && (
          <p className="text-sm text-destructive">{verifyError}</p>
        )}
        <div className={cn(INSET_SURFACE, "space-y-2 p-3")}>
          <Label htmlFor="custom-host">Hostname</Label>
          <Input
            id="custom-host"
            value={hostname}
            onChange={(e) => setHostname(e.target.value)}
            placeholder="mcp.example.com"
            className="bg-transparent dark:bg-transparent"
          />
        </div>
        <div className="flex flex-wrap gap-2">
          <Button
            type="button"
            size="sm"
            onClick={() => setMutation.mutate()}
            disabled={setMutation.isPending || !hostname.trim()}
          >
            {setMutation.isPending
              ? "Saving…"
              : data.hostname
                ? "Update Hostname"
                : "Save Hostname"}
          </Button>
          {canRefreshChecks && (
            <Button
              type="button"
              size="sm"
              variant="secondary"
              onClick={() => verifyMutation.mutate()}
              disabled={verifyMutation.isPending}
            >
              <RefreshCwIcon
                className={verifyMutation.isPending ? "animate-spin" : undefined}
              />
              {verifyMutation.isPending
                ? "Checking…"
                : data.verified
                  ? "Refresh DNS/TLS"
                  : "Verify DNS"}
            </Button>
          )}
        </div>
      </div>
    </section>
  );
}
