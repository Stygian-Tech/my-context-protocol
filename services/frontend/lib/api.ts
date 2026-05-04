import {
  logClientApiError,
  logClientApiErrorBody,
  logClientApiRequest,
  logClientApiResponse,
} from "@/lib/client-api-logging";

const getBaseUrl = () => {
  if (typeof window !== "undefined") {
    return "/api";
  }
  return process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:8080";
};

export class ApiError extends Error {
  constructor(
    message: string,
    public status: number,
    public body?: unknown
  ) {
    super(message);
    this.name = "ApiError";
  }
}

/** Readable detail from an API error body for dashboards and dialogs. */
export function formatApiErrorDetail(body: unknown): string {
  if (body == null || body === "") return "";
  if (typeof body === "string") return body;
  if (typeof body === "object") {
    const o = body as Record<string, unknown>;
    if (typeof o.reason === "string") return o.reason;
    if (typeof o.error === "string") return o.error;
    if (typeof o.message === "string") return o.message;
    try {
      return JSON.stringify(body, null, 2);
    } catch {
      return String(body);
    }
  }
  return String(body);
}

async function handleResponse<T>(response: Response): Promise<T> {
  const contentType = response.headers.get("content-type");
  const isJson = contentType?.includes("application/json");

  if (!response.ok) {
    const body = isJson ? await response.json().catch(() => null) : await response.text();
    throw new ApiError(
      `Request failed: ${response.status} ${response.statusText}`,
      response.status,
      body
    );
  }

  if (response.status === 204) {
    return undefined as T;
  }

  return (isJson ? response.json() : response.text()) as Promise<T>;
}

export async function apiFetch<T>(
  path: string,
  options: RequestInit = {}
): Promise<T> {
  const baseUrl = getBaseUrl();
  const url = `${baseUrl.replace(/\/$/, "")}${path.startsWith("/") ? path : `/${path}`}`;
  const method = (options.method ?? "GET").toUpperCase();
  logClientApiRequest(method, url, options);

  const t0 = typeof performance !== "undefined" ? performance.now() : Date.now();
  let response: Response;
  try {
    response = await fetch(url, {
      ...options,
      headers: {
        "Content-Type": "application/json",
        ...options.headers,
      },
      credentials: "include",
    });
  } catch (err) {
    const elapsed =
      typeof performance !== "undefined" ? performance.now() - t0 : Date.now() - t0;
    logClientApiError(method, url, Math.round(elapsed), err);
    throw err;
  }
  const elapsed =
    typeof performance !== "undefined" ? performance.now() - t0 : Date.now() - t0;
  logClientApiResponse(method, url, response.status, Math.round(elapsed), response.ok);

  try {
    return await handleResponse<T>(response);
  } catch (err) {
    if (err instanceof ApiError) {
      logClientApiErrorBody(err.body);
    }
    throw err;
  }
}

export const api = {
  get: <T>(path: string) => apiFetch<T>(path, { method: "GET" }),
  post: <T>(path: string, body?: unknown) =>
    apiFetch<T>(path, { method: "POST", body: body ? JSON.stringify(body) : undefined }),
  put: <T>(path: string, body?: unknown) =>
    apiFetch<T>(path, { method: "PUT", body: body ? JSON.stringify(body) : undefined }),
  patch: <T>(path: string, body?: unknown) =>
    apiFetch<T>(path, { method: "PATCH", body: body ? JSON.stringify(body) : undefined }),
  delete: <T>(path: string) => apiFetch<T>(path, { method: "DELETE" }),
};
