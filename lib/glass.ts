import { cn } from "./utils";

export type GlassSurfaceVariant = "subtle" | "default" | "elevated";

const glassEffectVariants: Record<GlassSurfaceVariant, string> = {
  subtle: "supports-backdrop-filter:backdrop-blur-sm",
  default: "supports-backdrop-filter:backdrop-blur-md",
  elevated: "supports-backdrop-filter:backdrop-blur-xl",
};

const glassSurfaceVariants: Record<GlassSurfaceVariant, string> = {
  subtle:
    "border border-border/60 bg-background/72 shadow-sm supports-backdrop-filter:bg-background/48",
  default:
    "border border-border/60 bg-background/80 shadow-sm supports-backdrop-filter:bg-background/62",
  elevated:
    "border border-border/60 bg-background/88 shadow-lg shadow-black/8 supports-backdrop-filter:bg-background/72 dark:shadow-black/30",
};

export function glassEffectClasses(variant: GlassSurfaceVariant = "default") {
  return glassEffectVariants[variant];
}

export function glassSurfaceClasses(
  variant: GlassSurfaceVariant = "default",
  className?: string
) {
  return cn(glassEffectClasses(variant), glassSurfaceVariants[variant], className);
}
