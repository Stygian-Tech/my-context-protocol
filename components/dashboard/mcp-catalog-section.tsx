"use client";

import { useQuery } from "@tanstack/react-query";
import { fetchProjectCatalog } from "@/lib/projects-api";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { CopyIcon } from "lucide-react";
import { ApiError, formatApiErrorDetail } from "@/lib/api";
import { copyTextToClipboard } from "@/lib/clipboard";

interface McpCatalogSectionProps {
  projectId: string;
}

export function McpCatalogSection({ projectId }: McpCatalogSectionProps) {
  const { data, isLoading, error } = useQuery({
    queryKey: ["project-catalog", projectId],
    queryFn: () => fetchProjectCatalog(projectId),
  });

  if (isLoading) {
    return <Skeleton className="h-64 w-full" />;
  }

  if (error) {
    return (
      <div className="space-y-2 rounded-md border border-destructive/40 bg-destructive/5 p-4 text-sm">
        <p className="font-medium text-destructive">Could not load MCP catalog.</p>
        {error instanceof ApiError ? (
          <pre className="text-muted-foreground max-h-48 overflow-auto whitespace-pre-wrap break-all text-xs">
            {formatApiErrorDetail(error.body) || error.message}
          </pre>
        ) : (
          <p className="text-muted-foreground text-xs">{String(error)}</p>
        )}
      </div>
    );
  }

  if (!data) {
    return null;
  }

  const url = data.mcp_url;
  const sampleInitialize = JSON.stringify(
    {
      jsonrpc: "2.0",
      id: 1,
      method: "initialize",
      params: {
        protocolVersion: "2024-11-05",
        capabilities: {},
        clientInfo: { name: "example", version: "1.0.0" },
      },
    },
    null,
    2
  );

  const sampleResourcesRead = (uri: string) =>
    JSON.stringify(
      {
        jsonrpc: "2.0",
        id: 2,
        method: "resources/read",
        params: { uri },
      },
      null,
      2
    );

  const total =
    data.tools.length + data.resources.length + data.prompts.length;

  return (
    <Card>
      <CardHeader>
        <CardTitle>MCP catalog</CardTitle>
        <CardDescription>
          What this project exposes over MCP for the{" "}
          <span className="font-medium">active release</span>. Sync and
          activate a release to populate tools, resources, and prompts.
          Resource entries can include agent routing from SKILL.md (
          <code className="font-mono text-xs">use_when</code>,{" "}
          <code className="font-mono text-xs">avoid_when</code>,{" "}
          <code className="font-mono text-xs">failure_modes</code>,{" "}
          <code className="font-mono text-xs">invoke_first</code>) — the same
          data is returned in <code className="font-mono text-xs">resources/list</code>{" "}
          and summarized at the top of <code className="font-mono text-xs">resources/read</code>.
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-6">
        {!data.release_id && (
          <p className="text-muted-foreground text-sm">
            No active release yet — connect a repo, sync, then activate a
            ready release.
          </p>
        )}
        {data.release_id && (
          <p className="text-muted-foreground text-sm">
            Release <span className="font-mono">{data.release_id}</span>
            {data.release_status
              ? ` · status: ${data.release_status}`
              : ""}
            {total === 0
              ? " · no capabilities in this release (check skill exposure types in compiled skills)."
              : ` · ${total} capability(ies).`}
          </p>
        )}

        <div className="space-y-2">
          <h4 className="text-sm font-medium">Connect</h4>
          <ol className="text-muted-foreground list-inside list-decimal space-y-1 text-sm">
            <li>Create an API key (API Keys tab).</li>
            <li>
              Send JSON-RPC <code className="font-mono text-xs">POST</code> to
              your MCP URL with header{" "}
              <code className="font-mono text-xs">
                Authorization: Bearer &lt;key&gt;
              </code>
              .
            </li>
            <li>
              Call <code className="font-mono text-xs">initialize</code>, then{" "}
              <code className="font-mono text-xs">tools/list</code>,{" "}
              <code className="font-mono text-xs">resources/list</code>, or{" "}
              <code className="font-mono text-xs">prompts/list</code>.
            </li>
          </ol>
          {url ? (
            <div className="flex flex-wrap items-center gap-2">
              <code className="bg-muted max-w-full flex-1 break-all rounded px-2 py-1 text-xs">
                {url}
              </code>
              <Button
                type="button"
                variant="outline"
                size="sm"
                onClick={() =>
                  void copyTextToClipboard(url, {
                    success: "Catalog URL copied to clipboard",
                    error: "Could not copy catalog URL",
                  })
                }
              >
                <CopyIcon className="mr-1 h-3.5 w-3.5" />
                Copy URL
              </Button>
            </div>
          ) : (
            <p className="text-muted-foreground text-xs">
              MCP URL unavailable — set{" "}
              <code className="font-mono">SAAS_MCP_BASE_DOMAIN</code> on the API
              or verify a custom domain.
            </p>
          )}
          <div className="space-y-1">
            <div className="flex items-center justify-between gap-2">
              <span className="text-muted-foreground text-xs">Sample initialize body</span>
              <Button
                type="button"
                variant="ghost"
                size="sm"
                className="h-7 text-xs"
                onClick={() =>
                  void copyTextToClipboard(sampleInitialize, {
                    success: "Sample JSON copied to clipboard",
                    error: "Could not copy sample JSON",
                  })
                }
              >
                <CopyIcon className="mr-1 h-3 w-3" />
                Copy JSON
              </Button>
            </div>
            <pre className="bg-muted max-h-40 overflow-auto rounded-md p-3 text-xs leading-relaxed">
              {sampleInitialize}
            </pre>
          </div>
        </div>

        <div className="space-y-2">
          <h4 className="text-sm font-medium">Tools</h4>
          {data.tools.length === 0 ? (
            <p className="text-muted-foreground text-sm">None.</p>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Name</TableHead>
                  <TableHead>Description</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {data.tools.map((t) => (
                  <TableRow key={t.name}>
                    <TableCell className="font-mono text-xs">{t.name}</TableCell>
                    <TableCell className="max-w-md text-sm">
                      {t.description ?? "—"}
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
        </div>

        <div className="space-y-2">
          <h4 className="text-sm font-medium">Resources</h4>
          {data.resources.length === 0 ? (
            <p className="text-muted-foreground text-sm">None.</p>
          ) : (
            <div className="space-y-4">
              {data.resources.map((r) => {
                const useWhen = r.use_when ?? [];
                const avoidWhen = r.avoid_when ?? [];
                const failureModes = r.failure_modes ?? [];
                const hasHints =
                  (useWhen.length > 0) ||
                  (avoidWhen.length > 0) ||
                  (failureModes.length > 0) ||
                  r.invoke_first === true;
                const readRpc = sampleResourcesRead(r.uri);
                return (
                  <div
                    key={r.uri}
                    className="bg-card space-y-3 rounded-lg border p-4 text-sm"
                  >
                    <div className="flex flex-wrap items-start justify-between gap-2">
                      <div className="min-w-0 flex-1 space-y-1">
                        <p className="font-medium leading-tight">
                          {r.name ?? "—"}
                        </p>
                        <code className="text-muted-foreground block break-all font-mono text-xs">
                          {r.uri}
                        </code>
                        {r.description ? (
                          <p className="text-muted-foreground text-xs leading-relaxed">
                            {r.description}
                          </p>
                        ) : null}
                      </div>
                      <div className="flex flex-shrink-0 flex-wrap gap-2">
                        {r.invoke_first ? (
                          <span className="bg-primary/10 text-primary rounded-md px-2 py-0.5 text-xs font-medium">
                            Invoke first
                          </span>
                        ) : null}
                        {hasHints && !r.invoke_first ? (
                          <span className="bg-muted rounded-md px-2 py-0.5 text-xs">
                            Agent hints
                          </span>
                        ) : null}
                        <Button
                          type="button"
                          variant="outline"
                          size="sm"
                          className="h-8"
                          onClick={() =>
                            void copyTextToClipboard(r.uri, {
                              success: "Resource URI copied",
                              error: "Could not copy URI",
                            })
                          }
                        >
                          <CopyIcon className="mr-1 h-3 w-3" />
                          Copy URI
                        </Button>
                        <Button
                          type="button"
                          variant="outline"
                          size="sm"
                          className="h-8"
                          onClick={() =>
                            void copyTextToClipboard(readRpc, {
                              success: "resources/read JSON copied",
                              error: "Could not copy JSON",
                            })
                          }
                        >
                          <CopyIcon className="mr-1 h-3 w-3" />
                          Copy read RPC
                        </Button>
                      </div>
                    </div>
                    {hasHints ? (
                      <div className="grid gap-3 border-t pt-3 sm:grid-cols-3">
                        {useWhen.length > 0 ? (
                          <div>
                            <p className="mb-1 text-xs font-medium text-foreground/90">
                              Read when
                            </p>
                            <ul className="text-muted-foreground list-inside list-disc space-y-0.5 text-xs">
                              {useWhen.map((line) => (
                                <li key={line}>{line}</li>
                              ))}
                            </ul>
                          </div>
                        ) : null}
                        {avoidWhen.length > 0 ? (
                          <div>
                            <p className="mb-1 text-xs font-medium text-foreground/90">
                              Skip when
                            </p>
                            <ul className="text-muted-foreground list-inside list-disc space-y-0.5 text-xs">
                              {avoidWhen.map((line) => (
                                <li key={line}>{line}</li>
                              ))}
                            </ul>
                          </div>
                        ) : null}
                        {failureModes.length > 0 ? (
                          <div className="sm:col-span-3">
                            <p className="mb-1 text-xs font-medium text-foreground/90">
                              Failure modes / fallbacks
                            </p>
                            <ul className="text-muted-foreground list-inside list-disc space-y-0.5 text-xs">
                              {failureModes.map((line) => (
                                <li key={line}>{line}</li>
                              ))}
                            </ul>
                          </div>
                        ) : null}
                      </div>
                    ) : (
                      <p className="text-muted-foreground border-t pt-2 text-xs">
                        No routing metadata on this resource yet. Add lists in
                        SKILL.md front matter (
                        <code className="font-mono">use_when</code>, etc.) and
                        re-sync the repo.
                      </p>
                    )}
                    <details className="text-xs">
                      <summary className="cursor-pointer font-medium text-foreground/90">
                        Sample <code className="font-mono">resources/read</code>{" "}
                        body
                      </summary>
                      <pre className="bg-muted mt-2 max-h-36 overflow-auto rounded-md p-2 leading-relaxed">
                        {readRpc}
                      </pre>
                    </details>
                  </div>
                );
              })}
            </div>
          )}
        </div>

        <div className="space-y-2">
          <h4 className="text-sm font-medium">Prompts</h4>
          {data.prompts.length === 0 ? (
            <p className="text-muted-foreground text-sm">None.</p>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Name</TableHead>
                  <TableHead>Description</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {data.prompts.map((p) => (
                  <TableRow key={p.name}>
                    <TableCell className="font-mono text-xs">{p.name}</TableCell>
                    <TableCell className="max-w-md text-sm">
                      {p.description ?? "—"}
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}
        </div>
      </CardContent>
    </Card>
  );
}
