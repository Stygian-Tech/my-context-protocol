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

interface RequestLogsTableProps {
  projectId: string;
}

export function RequestLogsTable({ projectId }: RequestLogsTableProps) {
  const { data: logs, isLoading } = useQuery({
    queryKey: ["request-logs", projectId],
    queryFn: () => fetchRequestLogs(projectId, { limit: 50 }),
  });

  if (isLoading) {
    return <Skeleton className="h-48" />;
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
            <TableCell className="text-muted-foreground text-sm">
              {log.error_code ?? "-"}
            </TableCell>
          </TableRow>
        ))}
      </TableBody>
    </Table>
  );
}
