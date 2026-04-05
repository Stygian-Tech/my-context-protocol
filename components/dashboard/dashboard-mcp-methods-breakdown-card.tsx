import type { CSSProperties } from "react";
import { cn } from "@/lib/utils";
import type { DashboardMethodCount } from "@/lib/types";

export function DashboardMcpMethodsBreakdownCard({
  methods,
  className,
  listClassName,
  style,
  title = "MCP Methods (7d Sample)",
}: {
  methods: DashboardMethodCount[];
  className?: string;
  /** Default matches the main dashboard (`max-h-56` scroll). Override for flex parents (e.g. project overview). */
  listClassName?: string;
  style?: CSSProperties;
  title?: string;
}) {
  return (
    <div className={cn("rounded-lg border p-4", className)} style={style}>
      <h3 className="font-medium">{title}</h3>
      <ul
        className={cn(
          "mt-3 max-h-56 space-y-2 overflow-y-auto text-sm",
          listClassName
        )}
      >
        {methods.length === 0 ? (
          <li className="text-muted-foreground">No traffic in sample window.</li>
        ) : (
          methods.map((row) => (
            <li
              key={row.method}
              className="flex items-center justify-between gap-2 font-mono text-xs"
            >
              <span className="min-w-0 truncate" title={row.method}>
                {row.method}
              </span>
              <span className="tabular-nums text-foreground">{row.count}</span>
            </li>
          ))
        )}
      </ul>
    </div>
  );
}
