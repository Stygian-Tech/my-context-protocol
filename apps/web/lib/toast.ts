"use client";

export type ToastVariant = "success" | "error";

export interface ToastItem {
  id: number;
  message: string;
  variant: ToastVariant;
}

type ToastListener = (toasts: ToastItem[]) => void;

let nextToastId = 1;
let toasts: ToastItem[] = [];
const listeners = new Set<ToastListener>();

function emit() {
  for (const listener of listeners) {
    listener(toasts);
  }
}

function pushToast(message: string, variant: ToastVariant) {
  const toast: ToastItem = {
    id: nextToastId++,
    message,
    variant,
  };

  toasts = [...toasts, toast];
  emit();

  window.setTimeout(() => {
    toasts = toasts.filter((item) => item.id !== toast.id);
    emit();
  }, 3000);
}

export function subscribeToToasts(listener: ToastListener) {
  listeners.add(listener);
  listener(toasts);

  return () => {
    listeners.delete(listener);
  };
}

export function toastSuccess(message: string) {
  pushToast(message, "success");
}

export function toastError(message: string) {
  pushToast(message, "error");
}
