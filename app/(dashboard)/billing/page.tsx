"use client";

import { useAuth } from "@/contexts/auth-context";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import { createCheckoutSession, createPortalSession } from "@/lib/billing-api";
import { useMutation } from "@tanstack/react-query";
import { useSearchParams } from "next/navigation";
import { useState } from "react";

const PRO_PRICE_MONTHLY_LABEL = "$5/mo";
const PRO_PRICE_YEARLY_LABEL = "$50/yr";

export default function BillingPage() {
  const { user } = useAuth();
  const searchParams = useSearchParams();
  const billingBanner = searchParams.get("billing");

  const [billingInterval, setBillingInterval] = useState<"month" | "year">("month");

  const checkout = useMutation({
    mutationFn: () =>
      createCheckoutSession({
        interval: billingInterval,
        success_path: "/billing?billing=success",
        cancel_path: "/billing?billing=cancel",
      }),
    onSuccess: (data) => {
      window.location.href = data.url;
    },
  });

  const portal = useMutation({
    mutationFn: createPortalSession,
    onSuccess: (data) => {
      window.location.href = data.url;
    },
  });

  const isPro = user?.plan === "pro";
  const canManageStripe = Boolean(user?.can_manage_subscription);
  const internalProOnly =
    isPro && Boolean(user?.internal_pro_bypass) && !canManageStripe;

  return (
    <div className="mx-auto max-w-lg space-y-6">
      <div>
        <h1 className="text-3xl font-bold tracking-tight">Billing</h1>
        <p className="text-muted-foreground mt-1">
          Manage your subscription and payment method.
        </p>
      </div>

      {billingBanner === "success" && (
        <p className="text-sm text-green-600 dark:text-green-500">
          Checkout completed. It may take a moment for your plan to update — refresh if needed.
        </p>
      )}
      {billingBanner === "cancel" && (
        <p className="text-muted-foreground text-sm">Checkout was canceled.</p>
      )}

      <Card>
        <CardHeader>
          <CardTitle>Current plan</CardTitle>
          <CardDescription>
            You are on the <span className="font-medium text-foreground">{user?.plan ?? "free"}</span>{" "}
            plan.
            {internalProOnly && (
              <span className="mt-2 block text-muted-foreground">
                Pro access is enabled via an internal allowlist (no Stripe subscription on this
                account).
              </span>
            )}
          </CardDescription>
        </CardHeader>
        <CardContent className="flex flex-col gap-4">
          {!isPro ? (
            <>
              <div>
                <p className="text-muted-foreground mb-2 text-sm">Pro pricing</p>
                <div className="flex flex-wrap gap-2">
                  <Button
                    type="button"
                    variant={billingInterval === "month" ? "default" : "outline"}
                    size="sm"
                    className="h-auto min-h-8 flex-col gap-0.5 py-2"
                    onClick={() => setBillingInterval("month")}
                  >
                    <span>Monthly</span>
                    <span className="text-xs font-normal opacity-90">{PRO_PRICE_MONTHLY_LABEL}</span>
                  </Button>
                  <Button
                    type="button"
                    variant={billingInterval === "year" ? "default" : "outline"}
                    size="sm"
                    className="h-auto min-h-8 flex-col gap-0.5 py-2"
                    onClick={() => setBillingInterval("year")}
                  >
                    <span>Yearly</span>
                    <span className="text-xs font-normal opacity-90">{PRO_PRICE_YEARLY_LABEL}</span>
                  </Button>
                </div>
              </div>
              <Button
                onClick={() => checkout.mutate()}
                disabled={checkout.isPending}
                className="w-fit"
              >
                {checkout.isPending
                  ? "Redirecting…"
                  : `Upgrade to Pro — ${billingInterval === "month" ? PRO_PRICE_MONTHLY_LABEL : PRO_PRICE_YEARLY_LABEL}`}
              </Button>
            </>
          ) : canManageStripe ? (
            <Button
              variant="outline"
              onClick={() => portal.mutate()}
              disabled={portal.isPending}
              className="w-fit"
            >
              {portal.isPending ? "Opening…" : "Manage subscription"}
            </Button>
          ) : internalProOnly ? null : (
            <p className="text-muted-foreground text-sm">
              Subscription management is not available for this account. If you recently upgraded,
              refresh the page.
            </p>
          )}
        </CardContent>
      </Card>

      <p className="text-muted-foreground text-xs leading-relaxed">
        Pro is {PRO_PRICE_MONTHLY_LABEL} or {PRO_PRICE_YEARLY_LABEL}. It includes GitHub webhooks for
        automatic sync, higher manual sync limits, and custom MCP hostnames (bring your own domain).
      </p>
    </div>
  );
}
