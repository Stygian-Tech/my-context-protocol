"use client";

import { AuthGuard } from "@/components/auth-guard";
import { EnvironmentBanner } from "@/components/dashboard/environment-banner";
import { SidebarProvider, SidebarInset } from "@/components/ui/sidebar";
import { AppSidebar } from "@/components/layout/app-sidebar";
import { Header } from "@/components/layout/header";

export default function DashboardLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <AuthGuard>
      <SidebarProvider>
        <AppSidebar />
        <SidebarInset>
          <EnvironmentBanner />
          <Header />
          <div className="flex min-w-0 flex-1 flex-col gap-4 px-5 py-6 md:gap-5 md:px-6 md:py-8">
            {children}
          </div>
        </SidebarInset>
      </SidebarProvider>
    </AuthGuard>
  );
}
