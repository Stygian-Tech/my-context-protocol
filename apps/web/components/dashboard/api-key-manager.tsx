"use client";

import { useState, type FormEvent } from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import {
  fetchApiKeys,
  createApiKey,
  updateApiKey,
  revokeApiKey,
} from "@/lib/projects-api";
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
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Label } from "@/components/ui/label";
import { Skeleton } from "@/components/ui/skeleton";
import { BanIcon, CopyIcon, KeyIcon, PencilIcon } from "lucide-react";
import { formatLocalDateTime } from "@/lib/format-local-time";
import { buildMcpJsonConfig, copyTextToClipboard } from "@/lib/clipboard";
import { getApiKeyDisplayName } from "@/lib/api-key-utils";
import { MYCONTEXT_CATALOG_TOOL_NAME } from "@/lib/mcp-tool-names";
import type { ApiKey } from "@/lib/types";
import { ApiError, formatApiErrorDetail } from "@/lib/api";
import { toastError, toastSuccess } from "@/lib/toast";

const API_KEY_NAME_MAX_LEN = 64;

interface ApiKeyManagerProps {
  projectId: string;
  mcpUrl?: string | null;
  projectSlug?: string | null;
  /** When true, MCP OAuth is enabled on the server; keys remain supported alongside OAuth tokens. */
  mcpOAuthEnabled?: boolean;
}

interface CreatedApiKeyResult {
  id: string;
  key: string;
  prefix: string;
  name: string | null;
}

export function ApiKeyManager({
  projectId,
  mcpUrl,
  projectSlug,
  mcpOAuthEnabled = false,
}: ApiKeyManagerProps) {
  const [createDialogOpen, setCreateDialogOpen] = useState(false);
  const [createDraftName, setCreateDraftName] = useState("");
  const [createdKey, setCreatedKey] = useState<CreatedApiKeyResult | null>(null);
  const [postCreateName, setPostCreateName] = useState("");
  const [renameTarget, setRenameTarget] = useState<ApiKey | null>(null);
  const [renameName, setRenameName] = useState("");
  const [showRevoked, setShowRevoked] = useState(false);
  const [revokeTarget, setRevokeTarget] = useState<ApiKey | null>(null);
  const queryClient = useQueryClient();

  const { data: keys, isLoading } = useQuery({
    queryKey: ["api-keys", projectId, showRevoked],
    queryFn: () =>
      fetchApiKeys(projectId, { includeRevoked: showRevoked }),
  });

  const resetCreateDialog = () => {
    setCreateDialogOpen(false);
    setCreateDraftName("");
    setCreatedKey(null);
    setPostCreateName("");
    createMutation.reset();
  };

  const openCreateDialog = () => {
    setCreateDraftName("");
    setCreatedKey(null);
    setPostCreateName("");
    createMutation.reset();
    setCreateDialogOpen(true);
  };

  const createMutation = useMutation({
    mutationFn: (name: string) => {
      const t = name.trim();
      return createApiKey(projectId, { name: t.length > 0 ? t : null });
    },
    onSuccess: (data) => {
      queryClient.invalidateQueries({ queryKey: ["api-keys", projectId] });
      setCreatedKey({
        id: data.id,
        key: data.key,
        prefix: data.prefix,
        name: data.name ?? null,
      });
      setPostCreateName(data.name?.trim() ?? "");
    },
  });

  const postCreateNameMutation = useMutation({
    mutationFn: (name: string) => {
      if (!createdKey) throw new Error("No key");
      return updateApiKey(projectId, createdKey.id, { name });
    },
    onSuccess: (updated) => {
      queryClient.invalidateQueries({ queryKey: ["api-keys", projectId] });
      const next = updated.name?.trim() ?? "";
      setCreatedKey((prev) =>
        prev ? { ...prev, name: updated.name ?? null } : prev,
      );
      setPostCreateName(next);
      toastSuccess("Display Name Saved");
    },
    onError: (err: unknown) => {
      const detail =
        err instanceof ApiError
          ? formatApiErrorDetail(err.body) || err.message
          : String(err);
      toastError(detail || "Could not update name");
    },
  });

  const renameMutation = useMutation({
    mutationFn: ({ keyId, name }: { keyId: string; name: string }) =>
      updateApiKey(projectId, keyId, { name }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["api-keys", projectId] });
      setRenameTarget(null);
      toastSuccess("API Key Name Updated");
    },
    onError: (err: unknown) => {
      const detail =
        err instanceof ApiError
          ? formatApiErrorDetail(err.body) || err.message
          : String(err);
      toastError(detail || "Could not update API key name");
    },
  });

  const revokeMutation = useMutation({
    mutationFn: (keyId: string) => revokeApiKey(projectId, keyId),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["api-keys", projectId] });
      setRevokeTarget(null);
      toastSuccess("API Key Revoked");
    },
    onError: (err: unknown) => {
      const detail =
        err instanceof ApiError
          ? formatApiErrorDetail(err.body) || err.message
          : String(err);
      toastError(detail || "Could not revoke API key");
    },
  });

  const handleRenameSubmit = (e: FormEvent) => {
    e.preventDefault();
    if (!renameTarget) return;
    const next = renameName.trim();
    if (next.length > API_KEY_NAME_MAX_LEN) {
      toastError(`Name must be at most ${API_KEY_NAME_MAX_LEN} characters`);
      return;
    }
    const prev = renameTarget.name?.trim() ?? "";
    if (next === prev) {
      setRenameTarget(null);
      return;
    }
    renameMutation.mutate({ keyId: renameTarget.id, name: next });
  };

  const postCreateNameDirty =
    createdKey != null &&
    postCreateName.trim() !== (createdKey.name?.trim() ?? "");

  const handleCreateSubmit = (e: FormEvent) => {
    e.preventDefault();
    if (createDraftName.trim().length > API_KEY_NAME_MAX_LEN) {
      toastError(`Name must be at most ${API_KEY_NAME_MAX_LEN} characters`);
      return;
    }
    createMutation.mutate(createDraftName);
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
            For agents: call MCP tool{" "}
            <code className="font-mono text-xs">{MYCONTEXT_CATALOG_TOOL_NAME}</code>{" "}
            first for a markdown overview of this project&apos;s tools, resources, and prompts.
          </p>
          {mcpOAuthEnabled ? (
            <p>
              OAuth is also available on your MCP host for supported clients (see the{" "}
              <strong className="font-medium text-foreground">Connect</strong> section on
              Overview). API keys continue to work unchanged.
            </p>
          ) : null}
        </div>
        <Button type="button" onClick={openCreateDialog} className="shrink-0 self-start sm:self-end">
          <KeyIcon className="h-4 w-4" aria-hidden />
          Create API Key
        </Button>
      </div>
      <label className="flex cursor-pointer items-center gap-2 text-sm text-muted-foreground">
        <input
          type="checkbox"
          className="accent-primary h-4 w-4 rounded border"
          checked={showRevoked}
          onChange={(e) => setShowRevoked(e.target.checked)}
        />
        Show Revoked Keys
      </label>
      {keys && keys.length > 0 ? (
        <Table>
          <TableCaption className="sr-only">
            API keys for this project: display name, key prefix, status, usage
            times, and actions.
          </TableCaption>
          <TableHeader>
            <TableRow>
              <TableHead>Name</TableHead>
              <TableHead>Prefix</TableHead>
              <TableHead>Status</TableHead>
              <TableHead>Created</TableHead>
              <TableHead>Last Used</TableHead>
              <TableHead className="text-end">Actions</TableHead>
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
                <TableCell className="text-end">
                  <div className="flex flex-wrap items-center justify-end gap-2">
                    <Button
                      type="button"
                      variant="outline"
                      size="sm"
                      className="h-8"
                      disabled={key.status !== "active"}
                      onClick={() => {
                        setRenameName(key.name ?? "");
                        setRenameTarget(key);
                      }}
                    >
                      <PencilIcon className="mr-1 h-3.5 w-3.5" aria-hidden />
                      Rename
                    </Button>
                    <Button
                      type="button"
                      variant="outline"
                      size="sm"
                      className="h-8 text-destructive hover:bg-destructive/10 hover:text-destructive"
                      disabled={key.status !== "active"}
                      onClick={() => setRevokeTarget(key)}
                    >
                      <BanIcon className="mr-1 h-3.5 w-3.5" aria-hidden />
                      Revoke
                    </Button>
                  </div>
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      ) : (
        <div className="rounded-lg border border-dashed p-8 text-center text-muted-foreground">
          <p>
            {mcpOAuthEnabled
              ? "No API keys to show here. Create one for Bearer auth, or use OAuth from the Connect section on Overview."
              : "No API keys to show here. Create one to use the MCP endpoint."}
          </p>
          <p className="mt-2 text-sm">
            If you revoked all keys, enable &quot;Show Revoked Keys&quot; above to
            see them.
          </p>
        </div>
      )}
      <Dialog
        open={createDialogOpen}
        onOpenChange={(open) => {
          if (!open) {
            resetCreateDialog();
          }
        }}
      >
        <DialogContent className="max-h-[min(90vh,calc(100vh-2rem))] overflow-y-auto">
          <DialogHeader>
            <DialogTitle>
              {createdKey ? "API Key Created" : "Create API Key"}
            </DialogTitle>
            <DialogDescription>
              {createdKey
                ? "Copy the secret now. You will not be able to see it again. You can still adjust the display name below."
                : "Add an optional label so you can recognize this key in the list. You can change it later."}
            </DialogDescription>
          </DialogHeader>
          {!createdKey ? (
            <form onSubmit={handleCreateSubmit} className="space-y-4">
              <div className="space-y-2">
                <Label htmlFor="api-key-create-name">Name (Optional)</Label>
                <Input
                  id="api-key-create-name"
                  value={createDraftName}
                  onChange={(e) => setCreateDraftName(e.target.value)}
                  placeholder="e.g. Laptop / CI / Claude Desktop"
                  maxLength={API_KEY_NAME_MAX_LEN}
                  disabled={createMutation.isPending}
                  autoFocus
                />
                <p className="text-muted-foreground text-xs">
                  Shown only in this dashboard. Leave blank for an unnamed key.
                </p>
              </div>
              {createMutation.isError ? (
                <p className="text-destructive text-sm">
                  {createMutation.error instanceof ApiError
                    ? formatApiErrorDetail(createMutation.error.body) ||
                      createMutation.error.message
                    : String(createMutation.error)}
                </p>
              ) : null}
              <DialogFooter className="gap-2 sm:gap-0">
                <Button
                  type="button"
                  variant="outline"
                  onClick={resetCreateDialog}
                  disabled={createMutation.isPending}
                >
                  Cancel
                </Button>
                <Button type="submit" disabled={createMutation.isPending}>
                  {createMutation.isPending ? "Generating…" : "Generate Key"}
                </Button>
              </DialogFooter>
            </form>
          ) : (
            <div className="space-y-4">
              <div className="space-y-2">
                <Label htmlFor="api-key-post-create-name">Display Name</Label>
                <div className="flex flex-col gap-2 sm:flex-row sm:items-center">
                  <Input
                    id="api-key-post-create-name"
                    value={postCreateName}
                    onChange={(e) => setPostCreateName(e.target.value)}
                    placeholder="Key name (optional)"
                    maxLength={API_KEY_NAME_MAX_LEN}
                    disabled={postCreateNameMutation.isPending}
                  />
                  <Button
                    type="button"
                    variant="secondary"
                    size="sm"
                    className="shrink-0"
                    disabled={
                      !postCreateNameDirty ||
                      postCreateNameMutation.isPending ||
                      postCreateName.trim().length > API_KEY_NAME_MAX_LEN
                    }
                    onClick={() => {
                      if (postCreateName.trim().length > API_KEY_NAME_MAX_LEN) {
                        toastError(
                          `Name must be at most ${API_KEY_NAME_MAX_LEN} characters`,
                        );
                        return;
                      }
                      postCreateNameMutation.mutate(postCreateName);
                    }}
                  >
                    {postCreateNameMutation.isPending ? "Saving…" : "Save Name"}
                  </Button>
                </div>
              </div>
              <div className="space-y-2">
                <div className="flex items-center justify-between gap-2">
                  <p className="text-sm font-medium">Secret</p>
                  <Button
                    size="sm"
                    variant="outline"
                    onClick={() =>
                      void copyTextToClipboard(createdKey.key, {
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
                  <code className="flex-1 break-all font-mono text-sm">
                    {createdKey.key}
                  </code>
                </div>
              </div>
              {mcpUrl ? (
                <div className="space-y-2">
                  <div className="flex items-center justify-between gap-2">
                    <p className="text-sm font-medium">mcp.json object</p>
                    <Button
                      size="sm"
                      variant="outline"
                      onClick={() =>
                        void copyTextToClipboard(
                          buildMcpJsonConfig(mcpUrl, createdKey.key, {
                            projectSlug,
                          }),
                          {
                            success: "mcp.json object copied to clipboard",
                            error: "Could not copy mcp.json object",
                          },
                        )
                      }
                    >
                      <CopyIcon className="h-4 w-4" />
                      Copy mcp.json Object
                    </Button>
                  </div>
                  <pre className="bg-muted max-h-48 overflow-auto rounded-lg p-4 text-xs leading-relaxed">
                    {buildMcpJsonConfig(mcpUrl, createdKey.key, { projectSlug })}
                  </pre>
                </div>
              ) : (
                <p className="text-muted-foreground text-sm">
                  The mcp.json snippet will be available once this project has an
                  MCP URL.
                </p>
              )}
              <DialogFooter>
                <Button type="button" onClick={resetCreateDialog}>
                  Done
                </Button>
              </DialogFooter>
            </div>
          )}
        </DialogContent>
      </Dialog>

      <Dialog
        open={revokeTarget != null}
        onOpenChange={(open) => !open && setRevokeTarget(null)}
      >
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Revoke API Key</DialogTitle>
            <DialogDescription>
              This cannot be undone. MCP clients using this key will stop working
              immediately.
            </DialogDescription>
          </DialogHeader>
          {revokeTarget ? (
            <p className="text-sm">
              Revoke{" "}
              <span className="font-medium">
                {getApiKeyDisplayName(revokeTarget.name)}
              </span>{" "}
              <span className="font-mono text-muted-foreground">
                ({revokeTarget.key_prefix}…)
              </span>
              ?
            </p>
          ) : null}
          <DialogFooter>
            <Button
              type="button"
              variant="outline"
              onClick={() => setRevokeTarget(null)}
              disabled={revokeMutation.isPending}
            >
              Cancel
            </Button>
            <Button
              type="button"
              variant="destructive"
              disabled={revokeMutation.isPending || !revokeTarget}
              onClick={() => {
                if (revokeTarget) {
                  revokeMutation.mutate(revokeTarget.id);
                }
              }}
            >
              {revokeMutation.isPending ? "Revoking…" : "Revoke Key"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <Dialog
        open={renameTarget != null}
        onOpenChange={(open) => !open && setRenameTarget(null)}
      >
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Rename API Key</DialogTitle>
            <DialogDescription>
              This label is only for your reference in the dashboard. Leave the
              field empty to show &quot;Unnamed key&quot;.
            </DialogDescription>
          </DialogHeader>
          <form onSubmit={handleRenameSubmit} className="space-y-4">
            <div className="space-y-2">
              <Label htmlFor="api-key-rename">Name</Label>
              <Input
                id="api-key-rename"
                value={renameName}
                onChange={(event) => setRenameName(event.target.value)}
                placeholder="Key name (optional)"
                maxLength={API_KEY_NAME_MAX_LEN}
                disabled={renameMutation.isPending}
              />
            </div>
            <DialogFooter>
              <Button
                type="button"
                variant="outline"
                onClick={() => setRenameTarget(null)}
                disabled={renameMutation.isPending}
              >
                Cancel
              </Button>
              <Button type="submit" disabled={renameMutation.isPending}>
                {renameMutation.isPending ? "Saving…" : "Save"}
              </Button>
            </DialogFooter>
          </form>
        </DialogContent>
      </Dialog>
    </div>
  );
}
