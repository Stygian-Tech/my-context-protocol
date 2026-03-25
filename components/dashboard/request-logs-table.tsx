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
import { Skeleton } from "@/components/ui/skeleton";
import { ApiError, formatApiErrorDetail } from "@/lib/api";

interface RequestLogsTableProps {
  projectId: string;
}

export function RequestLogsTable({ projectId }: RequestLogsTableProps) {
  const { data: logs, isLoading, error } = useQuery({
    queryKey: ["request-logs", projectId],
    queryFn: () => fetchRequestLogs(projectId, { limit: 100 }),
  });

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
          <TableRow key={log.id}>
            <TableCell className="text-sm">
              {new Date(log.timestamp).toLocaleString()}
            </TableCell>
            <TableCell className="font-mono text-sm">{log.method}</TableCell>
            <TableCell>
              <Badge variant={log.status >= 400 ? "destructive" : "default"}>
                {log.status}
              </Badge>
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
  );
}
