"use client";

import type { Components } from "react-markdown";
import ReactMarkdown from "react-markdown";
import rehypeSanitize from "rehype-sanitize";
import remarkGfm from "remark-gfm";
import { cn } from "@/lib/utils";

const markdownComponents: Components = {
  h1: ({ className, ...props }) => (
    <h1
      className={cn(
        "mb-2 mt-3 text-sm font-semibold tracking-tight text-foreground first:mt-0",
        className,
      )}
      {...props}
    />
  ),
  h2: ({ className, ...props }) => (
    <h2
      className={cn(
        "mb-2 mt-3 text-sm font-semibold tracking-tight text-foreground first:mt-0",
        className,
      )}
      {...props}
    />
  ),
  h3: ({ className, ...props }) => (
    <h3
      className={cn(
        "mb-1.5 mt-2 text-xs font-semibold text-foreground first:mt-0",
        className,
      )}
      {...props}
    />
  ),
  h4: ({ className, ...props }) => (
    <h4
      className={cn(
        "mb-1.5 mt-2 text-xs font-semibold text-foreground first:mt-0",
        className,
      )}
      {...props}
    />
  ),
  p: ({ className, ...props }) => (
    <p
      className={cn(
        "mb-2 text-xs leading-relaxed text-foreground last:mb-0",
        className,
      )}
      {...props}
    />
  ),
  ul: ({ className, ...props }) => (
    <ul
      className={cn(
        "mb-2 list-inside list-disc space-y-0.5 text-xs text-foreground last:mb-0",
        className,
      )}
      {...props}
    />
  ),
  ol: ({ className, ...props }) => (
    <ol
      className={cn(
        "mb-2 list-inside list-decimal space-y-0.5 text-xs text-foreground last:mb-0",
        className,
      )}
      {...props}
    />
  ),
  li: ({ className, ...props }) => (
    <li className={cn("leading-relaxed", className)} {...props} />
  ),
  blockquote: ({ className, ...props }) => (
    <blockquote
      className={cn(
        "mb-2 border-l-2 border-border pl-3 text-xs italic text-muted-foreground",
        className,
      )}
      {...props}
    />
  ),
  hr: ({ className, ...props }) => (
    <hr className={cn("my-3 border-border", className)} {...props} />
  ),
  a: ({ className, href, ...props }) => {
    const external =
      typeof href === "string" &&
      (href.startsWith("http://") || href.startsWith("https://"));
    return (
      <a
        className={cn(
          "text-primary underline decoration-primary/40 underline-offset-2 hover:decoration-primary",
          className,
        )}
        href={href}
        {...(external
          ? ({ rel: "noopener noreferrer", target: "_blank" } as const)
          : {})}
        {...props}
      />
    );
  },
  strong: ({ className, ...props }) => (
    <strong className={cn("font-semibold text-foreground", className)} {...props} />
  ),
  code: ({ className, children, ...props }) => {
    const isFenced =
      typeof className === "string" && /\blanguage-/.test(className);
    if (isFenced) {
      return (
        <code
          className={cn(
            "block whitespace-pre font-mono text-[0.7rem] leading-relaxed text-foreground",
            className,
          )}
          {...props}
        >
          {children}
        </code>
      );
    }
    return (
      <code
        className={cn(
          "rounded bg-muted/80 px-1 py-0.5 font-mono text-[0.7rem] text-foreground dark:bg-muted/50",
          className,
        )}
        {...props}
      >
        {children}
      </code>
    );
  },
  pre: ({ className, children, ...props }) => (
    <pre
      className={cn(
        "mb-2 max-w-full overflow-x-auto rounded-md border border-border/50 bg-muted/30 p-2 font-mono text-[0.7rem] leading-relaxed text-foreground last:mb-0 dark:bg-muted/25",
        className,
      )}
      {...props}
    >
      {children}
    </pre>
  ),
  table: ({ className, ...props }) => (
    <div className="mb-2 max-w-full overflow-x-auto last:mb-0">
      <table
        className={cn("w-full border-collapse text-left text-xs", className)}
        {...props}
      />
    </div>
  ),
  thead: ({ className, ...props }) => (
    <thead className={cn("border-b border-border", className)} {...props} />
  ),
  th: ({ className, ...props }) => (
    <th
      className={cn("border border-border/60 px-2 py-1 font-medium", className)}
      {...props}
    />
  ),
  td: ({ className, ...props }) => (
    <td
      className={cn("border border-border/40 px-2 py-1 align-top", className)}
      {...props}
    />
  ),
};

export function MarkdownPreview({
  markdown,
  className,
}: {
  markdown: string;
  className?: string;
}) {
  return (
    <div className={cn("text-card-foreground", className)}>
      <ReactMarkdown
        components={markdownComponents}
        rehypePlugins={[rehypeSanitize]}
        remarkPlugins={[remarkGfm]}
      >
        {markdown}
      </ReactMarkdown>
    </div>
  );
}
