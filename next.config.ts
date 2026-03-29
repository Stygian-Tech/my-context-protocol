import type { NextConfig } from "next";

const rawApiUrl = process.env.NEXT_PUBLIC_API_URL?.trim() ?? "";
const apiUrl = (rawApiUrl || "http://localhost:8080").replace(/\/$/, "");

/** Rewrites are fixed at build time; missing API URL on Vercel produces 502 on every `/api/*` call. */
if (process.env.VERCEL === "1") {
  if (!rawApiUrl) {
    throw new Error(
      "NEXT_PUBLIC_API_URL must be set for Vercel builds. Without it, /api/* rewrites target localhost and the edge returns 502."
    );
  }
  if (/localhost|127\.0\.0\.1/i.test(apiUrl)) {
    throw new Error(
      "NEXT_PUBLIC_API_URL must be a public API origin on Vercel (not localhost). Example: https://api.yourdomain.com"
    );
  }
}

/** Only these backend prefixes are exposed through the app origin (`/api/*`). */
const proxiedApiPrefixes = [
  "auth",
  "admin",
  "dashboard",
  "projects",
  "github",
  "billing",
  "webhooks",
] as const;

const nextConfig: NextConfig = {
  async rewrites() {
    return [
      { source: "/api/health", destination: `${apiUrl}/health` },
      ...proxiedApiPrefixes.map((prefix) => ({
        source: `/api/${prefix}/:path*`,
        destination: `${apiUrl}/${prefix}/:path*`,
      })),
    ];
  },
  async headers() {
    return [
      {
        source: "/:path*",
        headers: [
          { key: "X-Frame-Options", value: "DENY" },
          { key: "X-Content-Type-Options", value: "nosniff" },
          { key: "Referrer-Policy", value: "strict-origin-when-cross-origin" },
          {
            key: "Permissions-Policy",
            value: "camera=(), microphone=(), geolocation=()",
          },
        ],
      },
    ];
  },
};

export default nextConfig;
