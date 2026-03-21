import Link from "next/link";

export default function DashboardPage() {
  return (
    <div className="space-y-7">
      <div className="space-y-2">
        <h1 className="text-3xl font-bold tracking-tight">Dashboard</h1>
        <p className="max-w-xl text-muted-foreground leading-relaxed">
          Manage your MCP projects and skill repositories.
        </p>
      </div>
      <div className="flex flex-wrap gap-3">
        <Link
          href="/projects"
          className="inline-flex h-9 items-center justify-center rounded-lg border border-transparent bg-primary px-4 text-sm font-medium text-primary-foreground transition-colors hover:bg-primary/80"
        >
          View Projects
        </Link>
      </div>
    </div>
  );
}
