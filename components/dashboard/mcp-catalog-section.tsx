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

interface McpCatalogSectionProps {
  projectId: string;
}

function copy(text: string) {
  void navigator.clipboard.writeText(text);
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
              <Button type="button" variant="outline" size="sm" onClick={() => copy(url)}>
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
                onClick={() => copy(sampleInitialize)}
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
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>URI</TableHead>
                  <TableHead>Name</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {data.resources.map((r) => (
                  <TableRow key={r.uri}>
                    <TableCell className="max-w-xs break-all font-mono text-xs">
                      {r.uri}
                    </TableCell>
                    <TableCell className="text-sm">{r.name ?? "—"}</TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
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
