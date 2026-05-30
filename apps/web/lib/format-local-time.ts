/** Parse API ISO-8601 instants for display in the browser's locale and time zone. */

function parseInstant(iso: string): Date | null {
  const t = iso?.trim();
  if (!t) return null;
  const d = new Date(t);
  return Number.isNaN(d.getTime()) ? null : d;
}

/** Date + time suitable for tables (e.g. release created, API key rows, request logs). */
export function formatLocalDateTime(iso: string): string {
  const d = parseInstant(iso);
  if (!d) return iso;
  return new Intl.DateTimeFormat(undefined, {
    dateStyle: "medium",
    timeStyle: "short",
  }).format(d);
}

/** Short label for dashboard chart axes: hour buckets vs day buckets. */
export function formatDashboardBucketLabel(iso: string, hourPrecision: boolean): string {
  const d = parseInstant(iso);
  if (!d) return iso;
  if (hourPrecision) {
    return new Intl.DateTimeFormat(undefined, {
      month: "short",
      day: "numeric",
      hour: "2-digit",
      minute: "2-digit",
    }).format(d);
  }
  return new Intl.DateTimeFormat(undefined, {
    month: "short",
    day: "numeric",
  }).format(d);
}

/** Richer range line for chart tooltips (local tz). */
export function formatLocalBucketRangeTooltip(startIso: string, endIso: string): string {
  const start = parseInstant(startIso);
  const end = parseInstant(endIso);
  if (!start || !end) return startIso;
  const dateTime = new Intl.DateTimeFormat(undefined, {
    dateStyle: "medium",
    timeStyle: "short",
  });
  const timeOnly = new Intl.DateTimeFormat(undefined, { timeStyle: "short" });
  if (start.toDateString() === end.toDateString()) {
    return `${dateTime.format(start)} – ${timeOnly.format(end)}`;
  }
  return `${dateTime.format(start)} – ${dateTime.format(end)}`;
}
