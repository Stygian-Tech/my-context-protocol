import Link from "next/link";

export default function DashboardPage() {
  return (
    <div className="space-y-8">
      <div>
        <h1 className="text-3xl font-bold tracking-tight">Dashboard</h1>
        <p className="text-muted-foreground">
          Manage your MCP projects and skill repositories.
        </p>
      </div>
      <div className="flex gap-4">
        <Link
          href="/projects"
          className="inline-flex h-8 items-center justify-center rounded-lg border border-transparent bg-primary px-2.5 text-sm font-medium text-primary-foreground transition-colors hover:bg-primary/80"
        >
          View Projects
        </Link>
      </div>
    </div>
  );
}
