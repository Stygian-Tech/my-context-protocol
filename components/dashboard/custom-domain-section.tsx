"use client";

import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import {
  fetchCustomDomain,
  setProjectCustomDomain,
  verifyProjectCustomDomain,
} from "@/lib/projects-api";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Skeleton } from "@/components/ui/skeleton";

interface CustomDomainSectionProps {
  projectId: string;
}

export function CustomDomainSection({ projectId }: CustomDomainSectionProps) {
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
    <Card>
      <CardHeader>
        <CardTitle>Custom domain</CardTitle>
        <CardDescription>
          Point your own hostname at this project. Add the TXT record we show, then verify.
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-4">
        {data.hostname && (
          <div className="text-sm">
            <span className="text-muted-foreground">Hostname: </span>
            <span className="font-medium">{data.hostname}</span>
            {data.verified ? (
              <span className="ml-2 text-green-600 dark:text-green-500">Verified</span>
            ) : (
              <span className="text-muted-foreground ml-2">Pending verification</span>
            )}
          </div>
        )}
        {!data.verified && data.instructions && (
          <p className="bg-muted rounded-md p-3 font-mono text-xs break-all">{data.instructions}</p>
        )}
        <div className="space-y-2">
          <Label htmlFor="custom-host">Hostname</Label>
          <Input
            id="custom-host"
            value={hostname}
            onChange={(e) => setHostname(e.target.value)}
            placeholder="mcp.example.com"
          />
        </div>
        <div className="flex flex-wrap gap-2">
          <Button
            type="button"
            size="sm"
            onClick={() => setMutation.mutate()}
            disabled={setMutation.isPending || !hostname.trim()}
          >
            {setMutation.isPending ? "Saving…" : data.hostname ? "Update hostname" : "Save hostname"}
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
      </CardContent>
    </Card>
  );
}
