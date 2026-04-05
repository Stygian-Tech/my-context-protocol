"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useQuery } from "@tanstack/react-query";
import { useCallback, useEffect, useRef, useState } from "react";
import { useAuth } from "@/contexts/auth-context";
import { fetchProjects } from "@/lib/projects-api";
import {
  Sidebar,
  SidebarContent,
  SidebarFooter,
  SidebarGroup,
  SidebarGroupContent,
  SidebarHeader,
  SidebarMenu,
  SidebarMenuAction,
  SidebarMenuButton,
  SidebarMenuItem,
  SidebarMenuSub,
  SidebarMenuSubButton,
  SidebarMenuSubItem,
  SidebarResizeHandle,
  useSidebar,
} from "@/components/ui/sidebar";
import { cn } from "@/lib/utils";
import {
  LayoutDashboardIcon,
  FolderIcon,
  CreditCardIcon,
  ShieldIcon,
  ChevronRightIcon,
  UserCircleIcon,
  LogOutIcon,
} from "lucide-react";

const navItems = [
  { href: "/", label: "Overview", icon: LayoutDashboardIcon },
  { href: "/projects", label: "Projects", icon: FolderIcon },
] as const;

const footerNavItems = [
  { href: "/account", label: "Account", icon: UserCircleIcon },
  { href: "/billing", label: "Billing", icon: CreditCardIcon },
] as const;

const PROJECTS_ACCORDION_STORAGE_KEY = "mycontext.sidebar.projectsAccordionOpen";

/** Shared stagger for primary nav, footer rows, and project sub-rows. */
const SIDEBAR_MENU_STAGGER_MS = 28;
const SIDEBAR_NAV_CASCADE_STAGGER_CAP = 12;

const PROJECTS_SUB_ITEM_STAGGER_MS = SIDEBAR_MENU_STAGGER_MS;
/** Cap so long lists don’t keep rows invisible far down the scroll. */
const PROJECTS_SUB_ITEM_STAGGER_CAP = 12;
/** Must match `.sidebar-projects-sub-item-exit` duration in `app/globals.css`. */
const PROJECTS_SUB_ITEM_EXIT_DURATION_MS = 110;

function readStoredProjectsAccordionOpen(): boolean | null {
  if (typeof window === "undefined") return null;
  try {
    const v = localStorage.getItem(PROJECTS_ACCORDION_STORAGE_KEY);
    if (v === "0") return false;
    if (v === "1") return true;
  } catch {
    /* quota / private mode */
  }
  return null;
}

function writeStoredProjectsAccordionOpen(open: boolean) {
  try {
    localStorage.setItem(PROJECTS_ACCORDION_STORAGE_KEY, open ? "1" : "0");
  } catch {
    /* ignore */
  }
}

function navCascadeDelayMs(staggerIndex: number) {
  return `${Math.min(staggerIndex, SIDEBAR_NAV_CASCADE_STAGGER_CAP) * SIDEBAR_MENU_STAGGER_MS}ms`;
}

function ProjectsNavAccordion({
  pathname,
  navStaggerIndex,
}: {
  pathname: string;
  navStaggerIndex: number;
}) {
  const { data: projects, isLoading, isError } = useQuery({
    queryKey: ["projects"],
    queryFn: fetchProjects,
  });

  const isActive =
    pathname === "/projects" || pathname.startsWith("/projects/");

  const [subOpen, setSubOpen] = useState(() => pathname.startsWith("/projects"));
  /** True while the project list is still mounted after a close, playing exit animation. */
  const [subExiting, setSubExiting] = useState(false);
  const subCloseTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const clearSubCloseTimeout = useCallback(() => {
    if (subCloseTimeoutRef.current != null) {
      clearTimeout(subCloseTimeoutRef.current);
      subCloseTimeoutRef.current = null;
    }
  }, []);

  useEffect(() => {
    const stored = readStoredProjectsAccordionOpen();
    if (stored !== null) {
      setSubOpen(stored);
    }
  }, []);

  useEffect(() => {
    return () => clearSubCloseTimeout();
  }, [clearSubCloseTimeout]);

  useEffect(() => {
    const onStorage = (e: StorageEvent) => {
      if (e.key !== PROJECTS_ACCORDION_STORAGE_KEY) return;
      clearSubCloseTimeout();
      setSubExiting(false);
      if (e.newValue === "1") setSubOpen(true);
      else if (e.newValue === "0") setSubOpen(false);
    };
    window.addEventListener("storage", onStorage);
    return () => window.removeEventListener("storage", onStorage);
  }, [clearSubCloseTimeout]);

  const toggleSub = useCallback(
    (e: React.MouseEvent<HTMLButtonElement>) => {
      e.preventDefault();
      e.stopPropagation();
      setSubOpen((wasOpen) => {
        if (wasOpen) {
          writeStoredProjectsAccordionOpen(false);
          const list = projects;
          const canAnimateOut =
            !isLoading &&
            !isError &&
            list != null &&
            list.length > 0;
          if (canAnimateOut) {
            setSubExiting(true);
            clearSubCloseTimeout();
            const n = list.length;
            const maxStagger =
              Math.min(Math.max(0, n - 1), PROJECTS_SUB_ITEM_STAGGER_CAP) *
              PROJECTS_SUB_ITEM_STAGGER_MS;
            subCloseTimeoutRef.current = setTimeout(() => {
              setSubExiting(false);
              subCloseTimeoutRef.current = null;
            }, maxStagger + PROJECTS_SUB_ITEM_EXIT_DURATION_MS);
          }
          return false;
        }
        writeStoredProjectsAccordionOpen(true);
        clearSubCloseTimeout();
        setSubExiting(false);
        return true;
      });
    },
    [clearSubCloseTimeout, isError, isLoading, projects]
  );

  return (
    <SidebarMenuItem
      className="sidebar-nav-menu-item-cascade"
      style={{ animationDelay: navCascadeDelayMs(navStaggerIndex) }}
    >
      <SidebarMenuButton
        isActive={isActive}
        tooltip="Projects"
        render={
          <Link href="/projects">
            <FolderIcon />
            <span className="truncate">Projects</span>
          </Link>
        }
      />
      <SidebarMenuAction
        showOnHover={false}
        title={
          subOpen || subExiting
            ? "Collapse Projects List"
            : "Expand Projects List"
        }
        render={
          <button
            type="button"
            onClick={toggleSub}
            aria-expanded={subOpen || subExiting}
          >
            <ChevronRightIcon
              className={cn(
                "transition-transform duration-200",
                subOpen && "rotate-90"
              )}
            />
          </button>
        }
      />
      {subOpen || subExiting ? (
        <SidebarMenuSub className="max-h-48 overflow-y-auto border-sidebar-border">
          {isLoading ? (
            <SidebarMenuSubItem>
              <span className="text-muted-foreground px-2 text-xs">
                Loading…
              </span>
            </SidebarMenuSubItem>
          ) : isError ? (
            <SidebarMenuSubItem>
              <span className="text-muted-foreground px-2 text-xs">
                Could not load projects
              </span>
            </SidebarMenuSubItem>
          ) : projects && projects.length > 0 ? (
            projects.map((p, index) => {
              const exiting = subExiting && !subOpen;
              const staggerIndex = exiting
                ? Math.min(
                    Math.max(0, projects.length - 1 - index),
                    PROJECTS_SUB_ITEM_STAGGER_CAP
                  )
                : Math.min(index, PROJECTS_SUB_ITEM_STAGGER_CAP);
              return (
                <SidebarMenuSubItem
                  key={p.id}
                  className={
                    exiting
                      ? "sidebar-projects-sub-item-exit"
                      : "sidebar-projects-sub-item-enter"
                  }
                  style={{
                    animationDelay: `${staggerIndex * PROJECTS_SUB_ITEM_STAGGER_MS}ms`,
                  }}
                >
                  <SidebarMenuSubButton
                    isActive={pathname === `/projects/${p.id}`}
                    size="sm"
                    render={<Link href={`/projects/${p.id}`} />}
                  >
                    <span className="truncate" title={p.slug}>
                      {p.name}
                    </span>
                  </SidebarMenuSubButton>
                </SidebarMenuSubItem>
              );
            })
          ) : (
            <SidebarMenuSubItem>
              <span className="text-muted-foreground px-2 text-xs">
                No projects yet
              </span>
            </SidebarMenuSubItem>
          )}
        </SidebarMenuSub>
      ) : null}
    </SidebarMenuItem>
  );
}

export function AppSidebar() {
  const pathname = usePathname();
  const { user, logout } = useAuth();
  const { isMobile, state, openMobile } = useSidebar();

  const [sidebarCascadeGen, setSidebarCascadeGen] = useState(0);
  const sidebarWasOpenRef = useRef<boolean | null>(null);

  useEffect(() => {
    const open = isMobile ? openMobile : state === "expanded";
    const prev = sidebarWasOpenRef.current;
    if (open && prev === false) {
      setSidebarCascadeGen((n) => n + 1);
    }
    sidebarWasOpenRef.current = open;
  }, [isMobile, openMobile, state]);

  const items = user?.is_admin
    ? [
        ...navItems,
        { href: "/admin", label: "Admin", icon: ShieldIcon } as const,
      ]
    : navItems;

  return (
    <Sidebar>
      <SidebarHeader className="gap-2 pb-2 pt-2.5 pl-4 pr-2.5">
        <span className="font-semibold">MyContextProtocol</span>
      </SidebarHeader>
      <SidebarContent>
        <SidebarGroup>
          <SidebarGroupContent>
            <SidebarMenu>
              {items.map((item, navIndex) => {
                if (item.href === "/projects") {
                  return (
                    <ProjectsNavAccordion
                      key={`${item.href}-${sidebarCascadeGen}`}
                      pathname={pathname}
                      navStaggerIndex={navIndex}
                    />
                  );
                }
                const isActive =
                  item.href === "/"
                    ? pathname === "/"
                    : pathname.startsWith(item.href);
                return (
                  <SidebarMenuItem
                    key={`${item.href}-${sidebarCascadeGen}`}
                    className="sidebar-nav-menu-item-cascade"
                    style={{ animationDelay: navCascadeDelayMs(navIndex) }}
                  >
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
      <SidebarFooter className="border-sidebar-border border-t">
        <SidebarGroup className="p-0">
          <SidebarGroupContent>
            <SidebarMenu>
              {footerNavItems.map((item, footerIndex) => {
                const isActive = pathname.startsWith(item.href);
                const staggerIndex = items.length + footerIndex;
                return (
                  <SidebarMenuItem
                    key={`${item.href}-${sidebarCascadeGen}`}
                    className="sidebar-nav-menu-item-cascade"
                    style={{ animationDelay: navCascadeDelayMs(staggerIndex) }}
                  >
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
              <SidebarMenuItem
                key={`sign-out-${sidebarCascadeGen}`}
                className="sidebar-nav-menu-item-cascade"
                style={{
                  animationDelay: navCascadeDelayMs(
                    items.length + footerNavItems.length
                  ),
                }}
              >
                <SidebarMenuButton
                  tooltip="Sign out"
                  render={
                    <button type="button" onClick={() => void logout()}>
                      <LogOutIcon />
                      <span>Sign out</span>
                    </button>
                  }
                />
              </SidebarMenuItem>
            </SidebarMenu>
          </SidebarGroupContent>
        </SidebarGroup>
      </SidebarFooter>
      <SidebarResizeHandle />
    </Sidebar>
  );
}
