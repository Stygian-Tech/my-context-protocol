"use client";

import { Info } from "lucide-react";
import {
  Tooltip,
  TooltipContent,
  TooltipTrigger,
} from "@/components/ui/tooltip";
import { glassSurfaceClasses } from "@/lib/glass";
import { cn } from "@/lib/utils";

export function DashboardStatCard({
  title,
  value,
  hint,
  valueClassName = "text-2xl",
}: {
  title: string;
  value: string;
  hint?: string;
  valueClassName?: string;
}) {
  return (
    <div className={cn("rounded-lg p-4", glassSurfaceClasses("subtle"))}>
      <div className="flex items-start justify-between gap-2">
        <p className="text-muted-foreground min-w-0 flex-1 text-xs font-medium tracking-wide">
          {title}
        </p>
        {hint ? (
          <Tooltip>
            <TooltipTrigger
              className={cn(
                "text-muted-foreground hover:text-foreground -mr-1 -mt-0.5 inline-flex shrink-0 rounded-sm p-0.5 outline-none",
                "focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 focus-visible:ring-offset-background"
              )}
              aria-label={`About ${title}`}
            >
              <Info className="size-3.5" strokeWidth={2} aria-hidden />
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
          "mt-1 font-mono font-semibold tabular-nums",
          valueClassName
        )}
      >
        {value}
      </p>
    </div>
  );
}
