"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useAuth } from "@/contexts/auth-context";
import {
  Sidebar,
  SidebarContent,
  SidebarGroup,
  SidebarGroupContent,
  SidebarGroupLabel,
  SidebarHeader,
  SidebarMenu,
  SidebarMenuButton,
  SidebarMenuItem,
  SidebarResizeHandle,
} from "@/components/ui/sidebar";
import {
  LayoutDashboardIcon,
  FolderIcon,
  CreditCardIcon,
  ShieldIcon,
} from "lucide-react";

const navItems = [
  { href: "/", label: "Overview", icon: LayoutDashboardIcon },
  { href: "/projects", label: "Projects", icon: FolderIcon },
  { href: "/billing", label: "Billing", icon: CreditCardIcon },
];

export function AppSidebar() {
  const pathname = usePathname();
  const { user } = useAuth();

  const items = user?.is_admin
    ? [
        ...navItems,
        { href: "/admin", label: "Admin", icon: ShieldIcon } as const,
      ]
    : navItems;

  return (
    <Sidebar>
      <SidebarHeader>
        <span className="font-semibold">MyContextProtocol</span>
      </SidebarHeader>
      <SidebarContent>
        <SidebarGroup>
          <SidebarGroupLabel>Navigation</SidebarGroupLabel>
          <SidebarGroupContent>
            <SidebarMenu>
              {items.map((item) => {
                const isActive =
                  item.href === "/"
                    ? pathname === "/"
                    : pathname.startsWith(item.href);
                return (
                  <SidebarMenuItem key={item.href}>
                    <SidebarMenuButton
                      isActive={isActive}
                      tooltip={item.label}
                      render={
                        <Link href={item.href}>
                          <item.icon />
                          <span>{item.label}</span>
                        </Link>
                      }
                    />
                  </SidebarMenuItem>
                );
              })}
            </SidebarMenu>
          </SidebarGroupContent>
        </SidebarGroup>
      </SidebarContent>
      <SidebarResizeHandle />
    </Sidebar>
  );
}
