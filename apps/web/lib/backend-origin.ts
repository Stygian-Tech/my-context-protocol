/** Server-side backend origin. Prefer Railway private networking when configured. */
export function getBackendOrigin(): string {
  const raw =
    process.env.BACKEND_URL?.trim() ||
    process.env.API_ORIGIN?.trim() ||
    process.env.NEXT_PUBLIC_API_URL?.trim() ||
    "http://localhost:8080";
  return raw.replace(/\/$/, "");
}
