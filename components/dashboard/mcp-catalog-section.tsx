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
import { copyTextToClipboard, mcpEventsUrl } from "@/lib/clipboard";
import { pluralEn } from "@/lib/pluralize";

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

  const sampleInitializeResponse = JSON.stringify(
    {
      jsonrpc: "2.0",
      id: 1,
      result: {
        protocolVersion: "2024-11-05",
        capabilities: {
          tools: { listChanged: true },
          resources: { subscribe: true, listChanged: true },
          prompts: { listChanged: true },
        },
        serverInfo: {
          name: "MyContextProtocol",
          version: "1.0.0",
          title: "MyContextProtocol — Your project",
          description: "Hosted MCP skills for this project.",
          websiteUrl: "https://your-app.example.com/projects/<project-id>",
        },
        instructions:
          "You are connected to MyContextProtocol…\nDiscovery: call tool `mycontext:catalog` first…",
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
        <CardTitle>MCP Catalog</CardTitle>
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
              : ` · ${total} ${pluralEn(total, "capability", "capabilities")}.`}
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
              <code className="font-mono text-xs">tools/list</code> (includes{" "}
              <code className="font-mono text-xs">mycontext:catalog</code>),{" "}
              <code className="font-mono text-xs">resources/list</code>, or{" "}
              <code className="font-mono text-xs">prompts/list</code>.
            </li>
            <li>
              Optional: open a long-lived{" "}
              <code className="font-mono text-xs">GET</code> to{" "}
              <code className="font-mono text-xs">…/events</code> with the same
              bearer key for SSE <code className="font-mono text-xs">list_changed</code>{" "}
              notifications; otherwise compare{" "}
              <code className="font-mono text-xs">X-MCP-Catalog-Revision</code> on
              responses.
            </li>
          </ol>
          {url ? (
            <div className="space-y-2">
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
              <div className="flex flex-wrap items-center gap-2">
                <code className="bg-muted max-w-full flex-1 break-all rounded px-2 py-1 text-xs">
                  {mcpEventsUrl(url)}
                </code>
                <Button
                  type="button"
                  variant="outline"
                  size="sm"
                  onClick={() =>
                    void copyTextToClipboard(mcpEventsUrl(url), {
                      success: "MCP events URL copied",
                      error: "Could not copy events URL",
                    })
                  }
                >
                  <CopyIcon className="mr-1 h-3.5 w-3.5" />
                  Copy events URL
                </Button>
              </div>
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
              <span className="text-muted-foreground text-xs">Sample Initialize Body</span>
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
          <div className="space-y-1">
            <div className="flex items-center justify-between gap-2">
              <span className="text-muted-foreground text-xs">
                Example Initialize Response (Shape)
              </span>
              <Button
                type="button"
                variant="ghost"
                size="sm"
                className="h-7 text-xs"
                onClick={() =>
                  void copyTextToClipboard(sampleInitializeResponse, {
                    success: "Sample response copied to clipboard",
                    error: "Could not copy sample response",
                  })
                }
              >
                <CopyIcon className="mr-1 h-3 w-3" />
                Copy JSON
              </Button>
            </div>
            <pre className="bg-muted max-h-48 overflow-auto rounded-md p-3 text-xs leading-relaxed">
              {sampleInitializeResponse}
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
                      <div className="flex w-full flex-shrink-0 flex-wrap items-center justify-center gap-2 sm:w-auto sm:justify-end">
                        {r.invoke_first ? (
                          <span className="bg-primary/10 text-primary inline-flex items-center rounded-md px-2 py-1 text-xs font-medium leading-none">
                            Invoke first
                          </span>
                        ) : null}
                        {hasHints && !r.invoke_first ? (
                          <span className="bg-muted inline-flex items-center rounded-md px-2 py-1 text-xs leading-none">
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
