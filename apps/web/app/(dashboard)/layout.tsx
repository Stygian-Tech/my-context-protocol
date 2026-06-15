import { cookies } from "next/headers";
import { DashboardLayoutClient } from "./dashboard-layout-client";

export default async function DashboardLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const jar = await cookies();
  const sidebarCookie = jar.get("sidebar_state")?.value;
  const defaultSidebarOpen = sidebarCookie !== "false";

  return (
    <DashboardLayoutClient defaultSidebarOpen={defaultSidebarOpen}>
      {children}
    </DashboardLayoutClient>
  );
}
