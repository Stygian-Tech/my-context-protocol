import { cn } from "./utils";

export type GlassSurfaceVariant = "subtle" | "default" | "elevated";

/**
 * Strong backdrop blur for chrome glass (env banner + edge-peek sidebar).
 * Tuned so content behind reads heavily frosted; change here only.
 */
export const GLASS_CHROME_BACKDROP_BLUR_CLASSES =
  "supports-backdrop-filter:backdrop-blur-[5rem]" as const;

const glassEffectVariants: Record<GlassSurfaceVariant, string> = {
  subtle: GLASS_CHROME_BACKDROP_BLUR_CLASSES,
  default: "supports-backdrop-filter:backdrop-blur-md",
  elevated: "supports-backdrop-filter:backdrop-blur-xl",
};

const glassSurfaceVariants: Record<GlassSurfaceVariant, string> = {
  subtle:
    "border border-border/45 bg-background/42 shadow-sm supports-backdrop-filter:bg-background/26",
  default:
    "border border-border/45 bg-background/48 shadow-sm supports-backdrop-filter:bg-background/30",
  elevated:
    "border border-border/45 bg-background/55 shadow-lg shadow-black/8 supports-backdrop-filter:bg-background/36 dark:shadow-black/30",
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
