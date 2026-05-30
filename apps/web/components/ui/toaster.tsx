"use client";

import { useEffect, useState } from "react";
import { subscribeToToasts, type ToastItem } from "@/lib/toast";

function toastClassName(variant: ToastItem["variant"]) {
  if (variant === "error") {
    return "border-destructive/40 bg-destructive text-white";
  }

  return "border-emerald-500/40 bg-emerald-600 text-white";
}

export function Toaster() {
  const [toasts, setToasts] = useState<ToastItem[]>([]);

  useEffect(() => subscribeToToasts(setToasts), []);

  if (toasts.length === 0) {
    return null;
  }

  return (
    <div
      className="pointer-events-none fixed right-4 bottom-4 z-50 flex w-full max-w-sm flex-col gap-2"
      aria-label="Notifications"
      role="region"
    >
      {toasts.map((toast) => (
        <div
          key={toast.id}
          role="status"
          aria-live={toast.variant === "error" ? "assertive" : "polite"}
          className={`rounded-lg border px-3 py-2 text-sm shadow-lg ${toastClassName(toast.variant)}`}
        >
          {toast.message}
        </div>
      ))}
    </div>
  );
}
