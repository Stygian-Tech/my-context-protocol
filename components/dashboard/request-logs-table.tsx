"use client";

import { useQuery } from "@tanstack/react-query";
import { fetchRequestLogs } from "@/lib/projects-api";
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
import { Skeleton } from "@/components/ui/skeleton";
import { ApiError, formatApiErrorDetail } from "@/lib/api";
import { formatLocalDateTime } from "@/lib/format-local-time";
import type { RequestLog } from "@/lib/types";
import { copyTextToClipboard } from "@/lib/clipboard";

interface RequestLogsTableProps {
  projectId: string;
}

const TSV_HEADER =
  "timestamp\tmethod\thttp_status\tlatency_ms\tclient_id\terror_code\terror_message";

function tsvCell(value: string | null | undefined): string {
  if (value == null || value === "") return "";
  return String(value).replace(/\r\n|\r|\n/g, " ").replace(/\t/g, " ");
}

/** Tab-separated; suitable for spreadsheets and terminals. */
export function formatRequestLogsTsv(logs: RequestLog[], includeHeader: boolean): string {
  const lines: string[] = [];
  if (includeHeader) lines.push(TSV_HEADER);
  for (const log of logs) {
    lines.push(
      [
        tsvCell(formatLocalDateTime(log.timestamp)),
        tsvCell(log.method),
        tsvCell(String(log.status)),
        tsvCell(log.latency_ms != null ? String(log.latency_ms) : ""),
        tsvCell(log.client_id),
        tsvCell(log.error_code),
        tsvCell(log.error_message),
      ].join("\t")
    );
  }
  return lines.join("\n");
}

function statusBadgeVariant(
  status: number
): "default" | "secondary" | "destructive" {
  if (status >= 500) return "destructive";
  if (status >= 400) return "destructive";
  if (status >= 300) return "secondary";
  return "default";
}

export function RequestLogsTable({ projectId }: RequestLogsTableProps) {
  const { data: logs, isLoading, error } = useQuery({
    queryKey: ["request-logs", projectId],
    queryFn: () => fetchRequestLogs(projectId, { limit: 100 }),
  });

  const copyAll = () => {
    if (!logs?.length) return;
    const text = formatRequestLogsTsv(logs, true);
    void copyTextToClipboard(text, {
      success: `Copied ${logs.length} log row(s) to clipboard`,
      error: "Could not copy logs",
    });
  };

  if (isLoading) {
    return <Skeleton className="h-48" />;
  }

  if (error) {
    return (
      <div className="space-y-2 rounded-md border border-destructive/40 bg-destructive/5 p-4 text-sm">
        <p className="font-medium text-destructive">Could not load request logs.</p>
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

  if (!logs || logs.length === 0) {
    return (
      <div className="rounded-lg border p-8 text-center text-muted-foreground">
        No request logs yet. MCP requests will appear here.
      </div>
    );
  }

  return (
    <div className="space-y-3">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <p className="text-muted-foreground text-xs leading-snug">
          Right-click a row to copy that row (tab-separated). Use the button to copy every loaded
          row with a header line for spreadsheets.
        </p>
        <Button type="button" variant="outline" size="sm" onClick={copyAll}>
          Copy all logs
        </Button>
      </div>
      <Table>
        <TableHeader>
          <TableRow>
            <TableHead>Timestamp</TableHead>
            <TableHead>Method</TableHead>
            <TableHead>Status</TableHead>
            <TableHead>Latency</TableHead>
            <TableHead>Client</TableHead>
            <TableHead>Error</TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          {logs.map((log) => (
            <TableRow
              key={log.id}
              className="cursor-context-menu"
              title="Right-click to copy this row (TSV)"
              onContextMenu={(e) => {
                e.preventDefault();
                const text = formatRequestLogsTsv([log], true);
                void copyTextToClipboard(text, {
                  success: "Copied log row to clipboard",
                  error: "Could not copy row",
                });
              }}
            >
              <TableCell className="text-sm">
                {formatLocalDateTime(log.timestamp)}
              </TableCell>
              <TableCell className="font-mono text-sm">{log.method}</TableCell>
              <TableCell>
                <Badge variant={statusBadgeVariant(log.status)}>{log.status}</Badge>
              </TableCell>
              <TableCell>{log.latency_ms ?? "-"} ms</TableCell>
              <TableCell className="font-mono text-sm">{log.client_id ?? "-"}</TableCell>
              <TableCell className="max-w-[280px] align-top text-sm">
                <span className="text-muted-foreground block font-mono text-xs">
                  {log.error_code ?? "—"}
                </span>
                {log.error_message ? (
                  <span
                    className="text-destructive mt-0.5 line-clamp-4 whitespace-pre-wrap break-words"
                    title={log.error_message}
                  >
                    {log.error_message}
                  </span>
                ) : null}
              </TableCell>
            </TableRow>
          ))}
        </TableBody>
      </Table>
    </div>
  );
}
