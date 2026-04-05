import { ProjectDetailPageClient } from "./project-detail-page-client";

export default async function ProjectDetailPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  return <ProjectDetailPageClient projectId={id} />;
}
