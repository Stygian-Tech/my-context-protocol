"use client";

import Link from "next/link";
import { useAuth } from "@/contexts/auth-context";
import { SidebarTrigger } from "@/components/ui/sidebar";
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
import { Separator } from "@/components/ui/separator";
import { cn } from "@/lib/utils";

export function Header() {
  const { user, logout } = useAuth();

  const initials = user?.login
    ? user.login.slice(0, 2).toUpperCase()
    : user?.email
      ? user.email.slice(0, 2).toUpperCase()
      : "?";

  return (
    <header className="flex h-14 shrink-0 items-center gap-2 border-b px-4">
      <SidebarTrigger />
      <Separator orientation="vertical" className="h-6" />
      <div className="flex flex-1 items-center justify-between">
        <div />
        <DropdownMenu>
          <DropdownMenuTrigger
            className={cn(
              buttonVariants({ variant: "ghost", size: "icon" }),
              "rounded-full"
            )}
          >
            <Avatar className="h-8 w-8">
              {user?.avatar_url ? (
                <AvatarImage src={user.avatar_url} alt="" />
              ) : null}
              <AvatarFallback>{initials}</AvatarFallback>
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
              <UserCircleIcon className="mr-2 h-4 w-4" />
              Account
            </DropdownMenuItem>
            <DropdownMenuItem onClick={() => logout()}>
              <LogOutIcon className="mr-2 h-4 w-4" />
              Sign Out
            </DropdownMenuItem>
          </DropdownMenuContent>
        </DropdownMenu>
      </div>
    </header>
  );
}
