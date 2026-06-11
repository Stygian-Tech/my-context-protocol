"use client";

import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import {
  fetchCustomDomain,
  setProjectCustomDomain,
  verifyProjectCustomDomain,
} from "@/lib/projects-api";
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

interface CustomDomainSectionProps {
  projectId: string;
  isPro?: boolean;
}

export function CustomDomainSection({ projectId, isPro = true }: CustomDomainSectionProps) {
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
              Point your own hostname at this project with automatic TLS — available on Pro.
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

  if (isLoading || !data) {
    return <Skeleton className="h-40 w-full" />;
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
          then verify.
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
          </div>
        )}
        {!data.verified && data.instructions && (
          <p
            className={cn(
              INSET_SURFACE,
              "p-3 font-mono text-xs break-all",
            )}
          >
            {data.instructions}
          </p>
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
          {!data.verified && data.hostname && (
            <Button
              type="button"
              size="sm"
              variant="secondary"
              onClick={() => verifyMutation.mutate()}
              disabled={verifyMutation.isPending}
            >
              {verifyMutation.isPending ? "Checking…" : "Verify DNS"}
            </Button>
          )}
        </div>
      </div>
    </section>
  );
}
