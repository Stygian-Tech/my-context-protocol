"use client";

import Link from "next/link";
import { useAuth } from "@/contexts/auth-context";
import { SidebarTrigger, useSidebar } from "@/components/ui/sidebar";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuGroup,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { buttonVariants } from "@/components/ui/button";
import { Avatar, AvatarFallback, AvatarImage } from "@/components/ui/avatar";
import { LogOutIcon, UserCircleIcon } from "lucide-react";
import { glassSurfaceClasses } from "@/lib/glass";
import { cn } from "@/lib/utils";

export function Header() {
  const { user, logout } = useAuth();
  const { state, isMobile } = useSidebar();
  const showResizeHandle = !isMobile && state === "expanded";

  const initials = user?.login
    ? user.login.slice(0, 2).toUpperCase()
    : user?.email
      ? user.email.slice(0, 2).toUpperCase()
      : "?";

  return (
    <header
      className={cn(
        "flex h-14 shrink-0 items-center pr-3",
        showResizeHandle ? "pl-6" : "pl-3",
        glassSurfaceClasses(
          "default",
          "rounded-none border-x-0 border-t-0 supports-backdrop-filter:bg-background/46"
        )
      )}
    >
      {/* Match profile cap width so control centers mirror across the bar */}
      <div
        className={cn(
          "flex h-full w-14 shrink-0 items-center justify-center",
          showResizeHandle ? "-ml-6" : "-ml-3"
        )}
      >
        <SidebarTrigger className="size-8 shrink-0" />
      </div>
      <div className="min-w-0 flex-1" />
      <div className="flex h-full w-14 shrink-0 items-center justify-center">
        <DropdownMenu>
          <DropdownMenuTrigger
            className={cn(
              buttonVariants({ variant: "ghost", size: "icon" }),
              "rounded-full"
            )}
            aria-label={
              user?.login
                ? `Account menu, signed in as ${user.login}`
                : user?.email
                  ? `Account menu, signed in as ${user.email}`
                  : "Account menu"
            }
          >
            <Avatar className="h-8 w-8">
              {user?.avatar_url ? (
                <AvatarImage src={user.avatar_url} alt="" />
              ) : null}
              <AvatarFallback aria-hidden>{initials}</AvatarFallback>
            </Avatar>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end" className="w-56">
            <DropdownMenuGroup>
              <DropdownMenuLabel>
                <div className="flex flex-col gap-0.5">
                  <span className="text-foreground font-medium">
                    {user?.login ?? user?.email ?? "Signed in"}
                  </span>
                  <span className="text-muted-foreground text-xs font-normal">
                    GitHub
                  </span>
                </div>
              </DropdownMenuLabel>
            </DropdownMenuGroup>
            <DropdownMenuSeparator />
            <DropdownMenuItem
              nativeButton={false}
              render={<Link href="/account" />}
            >
              <UserCircleIcon className="mr-2 h-4 w-4" aria-hidden />
              Account
            </DropdownMenuItem>
            <DropdownMenuItem onClick={() => logout()}>
              <LogOutIcon className="mr-2 h-4 w-4" aria-hidden />
              Sign Out
            </DropdownMenuItem>
          </DropdownMenuContent>
        </DropdownMenu>
      </div>
    </header>
  );
}
