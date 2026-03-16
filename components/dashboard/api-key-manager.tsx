"use client";

import { useState } from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { fetchApiKeys, createApiKey } from "@/lib/projects-api";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Skeleton } from "@/components/ui/skeleton";
import { CopyIcon, KeyIcon } from "lucide-react";

interface ApiKeyManagerProps {
  projectId: string;
}

export function ApiKeyManager({ projectId }: ApiKeyManagerProps) {
  const [newKey, setNewKey] = useState<string | null>(null);
  const queryClient = useQueryClient();

  const { data: keys, isLoading } = useQuery({
    queryKey: ["api-keys", projectId],
    queryFn: () => fetchApiKeys(projectId),
  });

  const createMutation = useMutation({
    mutationFn: () => createApiKey(projectId),
    onSuccess: (data) => {
      queryClient.invalidateQueries({ queryKey: ["api-keys", projectId] });
      setNewKey(data.key);
    },
  });

  const copyToClipboard = (text: string) => {
    navigator.clipboard.writeText(text);
  };

  const closeNewKeyDialog = () => {
    setNewKey(null);
  };

  if (isLoading) {
    return <Skeleton className="h-48" />;
  }

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <p className="text-muted-foreground text-sm">
          API keys authenticate MCP clients. Store them securely—you won&apos;t
          see the full key again.
        </p>
        <Button
          onClick={() => createMutation.mutate()}
          disabled={createMutation.isPending}
        >
          <KeyIcon className="h-4 w-4" />
          {createMutation.isPending ? "Creating..." : "Create Key"}
        </Button>
      </div>
      {keys && keys.length > 0 ? (
        <Table>
          <TableHeader>
            <TableRow>
              <TableHead>Prefix</TableHead>
              <TableHead>Status</TableHead>
              <TableHead>Created</TableHead>
              <TableHead>Last Used</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {keys.map((key) => (
              <TableRow key={key.id}>
                <TableCell className="font-mono text-sm">
                  {key.key_prefix}...
                </TableCell>
                <TableCell>
                  <Badge variant={key.status === "active" ? "default" : "secondary"}>
                    {key.status}
                  </Badge>
                </TableCell>
                <TableCell>
                  {new Date(key.created_at).toLocaleString()}
                </TableCell>
                <TableCell>
                  {key.last_used_at
                    ? new Date(key.last_used_at).toLocaleString()
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
          {newKey && (
            <div className="flex items-center gap-2 rounded-lg bg-muted p-4">
              <code className="flex-1 font-mono text-sm break-all">{newKey}</code>
              <Button
                size="icon"
                variant="outline"
                onClick={() => copyToClipboard(newKey)}
              >
                <CopyIcon className="h-4 w-4" />
              </Button>
            </div>
          )}
        </DialogContent>
      </Dialog>
    </div>
  );
}
