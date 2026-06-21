"use client";

import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import {
  AlertTriangleIcon,
  CheckCircle2Icon,
  CircleDashedIcon,
  CopyIcon,
  RefreshCwIcon,
} from "lucide-react";
import {
  type CustomDomainStatus,
  fetchCustomDomain,
  setProjectCustomDomain,
  verifyProjectCustomDomain,
} from "@/lib/projects-api";
import { ApiError, formatApiErrorDetail } from "@/lib/api";
import { copyTextToClipboard } from "@/lib/clipboard";
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

type RoutingChoice = "address" | "cname";

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

function certificateStatusTone(status: CustomDomainStatus["certificate_status"]) {
  if (status === "issued") {
    return "text-green-600 dark:text-green-500";
  }
  if (status === "failed" || status === "not_configured") {
    return "text-destructive";
  }
  return "text-muted-foreground";
}

function hasText(value: string | null | undefined) {
  return Boolean(value?.trim());
}

function dnsRecordGroups(data: CustomDomainStatus) {
  const hostname = data.hostname?.trim();
  const verification: Array<{ type: string; name: string; value: string }> = [];
  const addressRouting: Array<{ type: string; name: string; value: string }> = [];
  const cnameRouting: Array<{ type: string; name: string; value: string }> = [];

  if (hostname && hasText(data.verification_token)) {
    verification.push({
      type: "TXT",
      name: data.verification_record_name?.trim() || `_mcp-verify.${hostname}`,
      value: data.verification_token!.trim(),
    });
  }
  if (hasText(data.fly_ownership_verification_record_name) && hasText(data.fly_ownership_verification_record_value)) {
    verification.push({
      type: "TXT",
      name: data.fly_ownership_verification_record_name!.trim(),
      value: data.fly_ownership_verification_record_value!.trim(),
    });
  }
  if (hostname) {
    for (const value of data.fly_a_record_values ?? []) {
      if (hasText(value)) {
        addressRouting.push({ type: "A", name: hostname, value: value.trim() });
      }
    }
    for (const value of data.fly_aaaa_record_values ?? []) {
      if (hasText(value)) {
        addressRouting.push({ type: "AAAA", name: hostname, value: value.trim() });
      }
    }
    if (hasText(data.fly_cname_record_value)) {
      cnameRouting.push({
        type: "CNAME",
        name: hostname,
        value: data.fly_cname_record_value!.trim(),
      });
    }
  }

  return { verification, addressRouting, cnameRouting };
}

function visibleInstructions(data: CustomDomainStatus) {
  const instructions = data.instructions?.trim();
  if (!instructions) {
    return null;
  }

  const message = data.certificate_message?.trim();
  if (!message) {
    return instructions;
  }

  const lines = instructions
    .split("\n")
    .map((line) => line.trim())
    .filter((line) => line && line !== message);
  return lines.length > 0 ? lines.join("\n") : null;
}

function formatDnsRecordsForCopy(records: Array<{ type: string; name: string; value: string }>) {
  return records
    .map((record) => `${record.type}\t${record.name}\t${record.value}`)
    .join("\n");
}

function TlsStatusIcon({
  status,
  isPending,
}: {
  status: CustomDomainStatus["certificate_status"];
  isPending: boolean;
}) {
  if (isPending || status === "pending") {
    return <CircleDashedIcon className={cn("size-4", isPending && "animate-spin")} />;
  }
  if (status === "issued") {
    return <CheckCircle2Icon className="size-4" />;
  }
  if (status === "failed" || status === "not_configured" || status === "unknown") {
    return <AlertTriangleIcon className="size-4" />;
  }
  return <CircleDashedIcon className="size-4" />;
}

function DnsRecordList({
  title,
  records,
  action,
  disabled,
}: {
  title: string;
  records: Array<{ type: string; name: string; value: string }>;
  action?: {
    label: string;
    onClick: () => void;
  };
  disabled?: boolean;
}) {
  return (
    <div
      className={cn(
        "overflow-hidden rounded-md border border-border/70",
        disabled && "opacity-50",
      )}
    >
      <div className="flex items-center justify-between gap-2 border-b border-border/70 bg-muted/25 px-2.5 py-1.5">
        <span className="text-xs font-medium text-foreground">{title}</span>
        {action && (
          <Button
            type="button"
            size="sm"
            variant="outline"
            onClick={action.onClick}
            disabled={disabled}
            className="h-7 px-2 text-xs"
          >
            <CopyIcon className="size-3.5" />
            {action.label}
          </Button>
        )}
      </div>
      <div className="divide-y divide-border/70">
        {records.map((record, index) => (
          <div
            key={`${record.type}-${record.name}-${record.value}-${index}`}
            className="grid gap-1 px-2.5 py-2 text-xs sm:grid-cols-[4.5rem_minmax(0,1fr)_minmax(0,1.4fr)] sm:gap-3"
          >
            <span className="font-medium text-foreground">{record.type}</span>
            <span className="break-all font-mono text-muted-foreground">{record.name}</span>
            <span className="break-all font-mono text-foreground">{record.value}</span>
          </div>
        ))}
      </div>
    </div>
  );
}

interface CustomDomainSectionProps {
  projectId: string;
  isPro?: boolean;
}

export function CustomDomainSection({ projectId, isPro = true }: CustomDomainSectionProps) {
  // Hooks must be called unconditionally before any early returns.
  const [hostname, setHostname] = useState("");
  const [routingChoice, setRoutingChoice] = useState<RoutingChoice | null>(null);
  const queryClient = useQueryClient();

  const { data, isLoading } = useQuery({
    queryKey: ["custom-domain", projectId],
    queryFn: () => fetchCustomDomain(projectId),
  });

  const setMutation = useMutation({
    mutationFn: () => setProjectCustomDomain(projectId, hostname.trim()),
    onSuccess: (next) => {
      queryClient.setQueryData(["custom-domain", projectId], next);
      queryClient.invalidateQueries({ queryKey: ["custom-domain", projectId] });
      queryClient.invalidateQueries({ queryKey: ["project", projectId] });
      setHostname("");
      setRoutingChoice(null);
    },
  });

  const verifyMutation = useMutation({
    mutationFn: () => verifyProjectCustomDomain(projectId),
    onSuccess: (next) => {
      queryClient.setQueryData(["custom-domain", projectId], next);
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

  const visibleData = verifyMutation.data ?? setMutation.data ?? data;
  const tlsLabel = certificateStatusLabel(visibleData.certificate_status);
  const canRefreshChecks =
    Boolean(visibleData.hostname) &&
    (!visibleData.verified ||
      visibleData.certificate_status === "pending" ||
      visibleData.certificate_status === "failed" ||
      visibleData.certificate_status === "not_configured" ||
      visibleData.certificate_status === "unknown");
  const verifyError =
    verifyMutation.error instanceof ApiError
      ? formatApiErrorDetail(verifyMutation.error.body) || verifyMutation.error.message
      : verifyMutation.error
        ? "Could not refresh DNS and TLS checks."
        : null;
  const isChecking = verifyMutation.isPending;
  const showCheckDetails =
    Boolean(visibleData.hostname) &&
    (isChecking ||
      visibleData.verified ||
      hasText(visibleData.certificate_message) ||
      hasText(visibleData.fly_ownership_verification_record_name));
  const recordGroups = dnsRecordGroups(visibleData);
  const hasRoutingOptions =
    recordGroups.addressRouting.length > 0 || recordGroups.cnameRouting.length > 0;
  const hasDnsRecords = recordGroups.verification.length > 0 || hasRoutingOptions;
  const addressDisabled = routingChoice === "cname";
  const cnameDisabled = routingChoice === "address";
  const instructions = visibleInstructions(visibleData);

  function copyRoutingRecords(choice: RoutingChoice) {
    const records =
      choice === "address" ? recordGroups.addressRouting : recordGroups.cnameRouting;
    setRoutingChoice(choice);
    void copyTextToClipboard(formatDnsRecordsForCopy(records), {
      success: choice === "address"
        ? "A/AAAA records copied to clipboard"
        : "CNAME record copied to clipboard",
      error: "Could not copy DNS records",
    });
  }

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
        {visibleData.hostname && (
          <div>
            <span className="text-muted-foreground">Hostname: </span>
            <span className="font-medium">{visibleData.hostname}</span>
            {visibleData.verified ? (
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
                className={cn("ml-2", certificateStatusTone(visibleData.certificate_status))}
              >
                {tlsLabel}
              </span>
            )}
          </div>
        )}
        {hasDnsRecords && (
          <div className={cn(INSET_SURFACE, "space-y-3 p-3")}>
            <div className="border-b border-border/80 px-3 py-2 text-sm font-medium text-foreground">
              DNS records
            </div>
            {recordGroups.verification.length > 0 && (
              <DnsRecordList
                title="Required verification records"
                records={recordGroups.verification}
              />
            )}
            {hasRoutingOptions && (
              <div className="space-y-2">
                <div>
                  <p className="text-xs font-medium text-foreground">Routing options</p>
                  <p className="text-xs text-muted-foreground">
                    Choose one option for the hostname. Copying one option disables the other to avoid invalid DNS records.
                  </p>
                </div>
                {routingChoice && (
                  <div className="flex flex-wrap items-center gap-2 text-xs text-muted-foreground">
                    <span>
                      Selected: {routingChoice === "address" ? "A/AAAA records" : "CNAME record"}
                    </span>
                    <Button
                      type="button"
                      size="sm"
                      variant="ghost"
                      onClick={() => setRoutingChoice(null)}
                      className="h-7 px-2 text-xs"
                    >
                      Restart DNS flow
                    </Button>
                  </div>
                )}
                {recordGroups.addressRouting.length > 0 && (
                  <DnsRecordList
                    title="Option 1: A/AAAA records"
                    records={recordGroups.addressRouting}
                    disabled={addressDisabled}
                    action={{
                      label: routingChoice === "address" ? "Copy again" : "Copy A/AAAA",
                      onClick: () => copyRoutingRecords("address"),
                    }}
                  />
                )}
                {recordGroups.cnameRouting.length > 0 && (
                  <DnsRecordList
                    title="Option 2: CNAME record"
                    records={recordGroups.cnameRouting}
                    disabled={cnameDisabled}
                    action={{
                      label: routingChoice === "cname" ? "Copy again" : "Copy CNAME",
                      onClick: () => copyRoutingRecords("cname"),
                    }}
                  />
                )}
              </div>
            )}
          </div>
        )}
        {showCheckDetails && (
          <div
            className={cn(INSET_SURFACE, "space-y-2 p-3")}
            aria-live="polite"
          >
            <div className="flex items-center gap-2 text-sm font-medium text-foreground">
              <TlsStatusIcon
                status={visibleData.certificate_status}
                isPending={isChecking}
              />
              {isChecking ? "Checking DNS and TLS" : "Latest DNS/TLS check"}
            </div>
            <ul className="space-y-1.5 text-xs text-muted-foreground">
              <li>
                DNS TXT verification:{" "}
                <span className={visibleData.verified ? "text-green-600 dark:text-green-500" : undefined}>
                  {visibleData.verified ? "verified" : isChecking ? "checking" : "waiting"}
                </span>
              </li>
              {hasText(visibleData.fly_ownership_verification_record_name) && (
                <li>
                  Fly ownership TXT:{" "}
                  <span className={visibleData.verified ? "text-green-600 dark:text-green-500" : undefined}>
                    {visibleData.verified ? "verified" : isChecking ? "checking" : "waiting"}
                  </span>
                </li>
              )}
              <li>
                Fly routing:{" "}
                <span className={visibleData.verified ? "text-green-600 dark:text-green-500" : undefined}>
                  {visibleData.verified ? "verified" : isChecking ? "checking" : "waiting"}
                </span>
              </li>
              <li>
                Fly TLS certificate:{" "}
                <span className={certificateStatusTone(visibleData.certificate_status)}>
                  {isChecking
                    ? "requesting status"
                    : tlsLabel?.replace(/^TLS /, "").toLowerCase() ?? "not checked"}
                </span>
              </li>
            </ul>
            {hasText(visibleData.certificate_message) && (
              <p className="text-xs text-muted-foreground">
                {visibleData.certificate_message}
              </p>
            )}
          </div>
        )}
        {instructions && (
          <p
            className={cn(
              INSET_SURFACE,
              "whitespace-pre-wrap p-3 font-mono text-xs break-all",
            )}
          >
            {instructions}
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
                : visibleData.verified
                  ? "Refresh DNS/TLS"
                  : "Verify DNS"}
            </Button>
          )}
        </div>
      </div>
    </section>
  );
}
