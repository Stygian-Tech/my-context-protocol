"use client";

import { Info } from "lucide-react";
import {
  Tooltip,
  TooltipContent,
  TooltipTrigger,
} from "@/components/ui/tooltip";
import { cn } from "@/lib/utils";

export function DashboardStatCard({
  title,
  value,
  hint,
  valueClassName = "text-2xl",
  compact = false,
}: {
  title: string;
  value: string;
  hint?: string;
  valueClassName?: string;
  /** Tighter padding and labels for dense metric grids. */
  compact?: boolean;
}) {
  return (
    <div
      className={cn(
        "rounded-lg border bg-card/50 shadow-xs",
        compact
          ? "flex min-h-0 min-w-0 flex-col gap-0.5 p-2"
          : "p-4"
      )}
    >
      <div className="flex items-center justify-between gap-1">
        <p
          className={cn(
            "text-muted-foreground min-w-0 flex-1 font-medium tracking-wide uppercase",
            compact
              ? "text-[10px] leading-none"
              : "text-xs"
          )}
        >
          {title}
        </p>
        {hint ? (
          <Tooltip>
            <TooltipTrigger
              className={cn(
                "text-muted-foreground hover:text-foreground inline-flex shrink-0 rounded-sm p-0 outline-none",
                compact ? "translate-x-0.5" : "-mr-1 -mt-0.5 p-0.5",
                "focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 focus-visible:ring-offset-background"
              )}
              aria-label={`About ${title}`}
            >
              <Info
                className={compact ? "size-3" : "size-3.5"}
                strokeWidth={2}
                aria-hidden
              />
            </TooltipTrigger>
            <TooltipContent
              side="top"
              align="end"
              sideOffset={6}
              className="max-w-sm text-left text-xs leading-snug whitespace-normal"
            >
              {hint}
            </TooltipContent>
          </Tooltip>
        ) : null}
      </div>
      <p
        className={cn(
          "min-w-0 font-mono font-semibold tabular-nums tracking-tight",
          compact
            ? "text-xl leading-none sm:text-2xl sm:leading-none"
            : cn("mt-1", valueClassName)
        )}
      >
        {value}
      </p>
    </div>
  );
}
