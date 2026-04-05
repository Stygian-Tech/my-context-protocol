"use client";

import { useState } from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { fetchApiKeys, createApiKey } from "@/lib/projects-api";
import {
  Table,
  TableBody,
  TableCaption,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Skeleton } from "@/components/ui/skeleton";
import { CopyIcon, KeyIcon } from "lucide-react";
import { formatLocalDateTime } from "@/lib/format-local-time";
import { buildMcpJsonConfig, copyTextToClipboard } from "@/lib/clipboard";
import { getApiKeyDisplayName } from "@/lib/api-key-utils";

interface ApiKeyManagerProps {
  projectId: string;
  mcpUrl?: string | null;
  projectSlug?: string | null;
}

interface CreatedApiKey {
  key: string;
  name?: string | null;
}

export function ApiKeyManager({ projectId, mcpUrl, projectSlug }: ApiKeyManagerProps) {
  const [newKey, setNewKey] = useState<CreatedApiKey | null>(null);
  const [keyName, setKeyName] = useState("");
  const queryClient = useQueryClient();

  const { data: keys, isLoading } = useQuery({
    queryKey: ["api-keys", projectId],
    queryFn: () => fetchApiKeys(projectId),
  });

  const createMutation = useMutation({
    mutationFn: () => createApiKey(projectId, { name: keyName }),
    onSuccess: (data) => {
      queryClient.invalidateQueries({ queryKey: ["api-keys", projectId] });
      setNewKey({ key: data.key, name: data.name });
      setKeyName("");
    },
  });

  const closeNewKeyDialog = () => {
    setNewKey(null);
  };

  if (isLoading) {
    return <Skeleton className="h-48" />;
  }

  return (
    <div className="space-y-4">
      <div className="flex flex-col gap-3 md:flex-row md:items-end md:justify-between">
        <div className="text-muted-foreground space-y-1 text-sm">
          <p>
            API keys authenticate MCP clients. Store them securely—you won&apos;t
            see the full key again.
          </p>
          <p>
            For agents: call MCP tool <code className="font-mono text-xs">mycontext:catalog</code>{" "}
            first for a markdown overview of this project&apos;s tools, resources, and prompts.
          </p>
        </div>
        <div className="flex w-full max-w-md flex-col gap-2 sm:flex-row">
          <Input
            value={keyName}
            onChange={(event) => setKeyName(event.target.value)}
            placeholder="Key name (optional)"
            maxLength={64}
          />
          <Button
            onClick={() => createMutation.mutate()}
            disabled={createMutation.isPending}
          >
            <KeyIcon className="h-4 w-4" aria-hidden />
            {createMutation.isPending ? "Creating..." : "Create Key"}
          </Button>
        </div>
      </div>
      {keys && keys.length > 0 ? (
        <Table>
          <TableCaption className="sr-only">
            API keys for this project: display name, key prefix, status, and
            usage times.
          </TableCaption>
          <TableHeader>
            <TableRow>
              <TableHead>Name</TableHead>
              <TableHead>Prefix</TableHead>
              <TableHead>Status</TableHead>
              <TableHead>Created</TableHead>
              <TableHead>Last Used</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {keys.map((key) => (
              <TableRow key={key.id}>
                <TableCell>{getApiKeyDisplayName(key.name)}</TableCell>
                <TableCell className="font-mono text-sm">
                  {key.key_prefix}...
                </TableCell>
                <TableCell>
                  <Badge variant={key.status === "active" ? "default" : "secondary"}>
                    {key.status}
                  </Badge>
                </TableCell>
                <TableCell>
                  {formatLocalDateTime(key.created_at)}
                </TableCell>
                <TableCell>
                  {key.last_used_at
                    ? formatLocalDateTime(key.last_used_at)
                    : "Never"}
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      ) : (
        <div className="rounded-lg border border-dashed p-8 text-center text-muted-foreground">
          No API keys yet. Create one to use the MCP endpoint.
        </div>
      )}
      <Dialog open={!!newKey} onOpenChange={(open) => !open && closeNewKeyDialog()}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>API Key Created</DialogTitle>
            <DialogDescription>
              Copy this key now. You won&apos;t be able to see it again.
            </DialogDescription>
          </DialogHeader>
          {newKey ? (
            <div className="space-y-4">
              <div className="space-y-2">
                <div className="flex items-center justify-between gap-2">
                  <p className="text-sm font-medium">
                    {getApiKeyDisplayName(newKey.name)}
                  </p>
                  <Button
                    size="sm"
                    variant="outline"
                    onClick={() =>
                      void copyTextToClipboard(newKey.key, {
                        success: "API key copied to clipboard",
                        error: "Could not copy API key",
                      })
                    }
                  >
                    <CopyIcon className="h-4 w-4" />
                    Copy Key
                  </Button>
                </div>
                <div className="flex items-center gap-2 rounded-lg bg-muted p-4">
                  <code className="flex-1 break-all font-mono text-sm">{newKey.key}</code>
                </div>
              </div>
              {mcpUrl ? (
                <div className="space-y-2">
                  <div className="flex items-center justify-between gap-2">
                    <p className="text-sm font-medium">mcp.json Object</p>
                    <Button
                      size="sm"
                      variant="outline"
                      onClick={() =>
                        void copyTextToClipboard(
                          buildMcpJsonConfig(mcpUrl, newKey.key, { projectSlug }),
                          {
                            success: "mcp.json object copied to clipboard",
                            error: "Could not copy mcp.json object",
                          }
                        )
                      }
                    >
                      <CopyIcon className="h-4 w-4" />
                      Copy mcp.json Object
                    </Button>
                  </div>
                  <pre className="bg-muted overflow-auto rounded-lg p-4 text-xs leading-relaxed">
                    {buildMcpJsonConfig(mcpUrl, newKey.key, { projectSlug })}
                  </pre>
                </div>
              ) : (
                <p className="text-muted-foreground text-sm">
                  The `mcp.json` snippet will be available once this project has an
                  MCP URL.
                </p>
              )}
            </div>
          ) : null}
        </DialogContent>
      </Dialog>
    </div>
  );
}
