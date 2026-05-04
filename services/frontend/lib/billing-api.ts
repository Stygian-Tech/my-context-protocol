import { api } from "./api";

export type BillingInterval = "month" | "year";

export async function createCheckoutSession(body?: {
  interval?: BillingInterval;
  success_path?: string;
  cancel_path?: string;
}): Promise<{ url: string }> {
  return api.post<{ url: string }>("/billing/checkout-session", body ?? {});
}

export async function createPortalSession(): Promise<{ url: string }> {
  return api.post<{ url: string }>("/billing/portal-session");
}
