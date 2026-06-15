import { Suspense } from "react";
import { ProjectDetailPageClient } from "./project-detail-page-client";
import { Skeleton } from "@/components/ui/skeleton";

export default async function ProjectDetailPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  return (
    <Suspense
      fallback={
        <div className="space-y-6" aria-busy="true" aria-live="polite">
          <Skeleton className="h-8 w-64" />
          <Skeleton className="h-64" />
        </div>
      }
    >
      <ProjectDetailPageClient projectId={id} />
    </Suspense>
  );
}
