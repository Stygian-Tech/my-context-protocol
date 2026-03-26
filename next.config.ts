import type { NextConfig } from "next";

const apiUrl = (process.env.NEXT_PUBLIC_API_URL || "http://localhost:8080").replace(/\/$/, "");

/** Only these backend prefixes are exposed through the app origin (`/api/*`). */
const proxiedApiPrefixes = [
  "auth",
  "dashboard",
  "projects",
  "github",
  "billing",
  "webhooks",
] as const;

const nextConfig: NextConfig = {
  async rewrites() {
    return proxiedApiPrefixes.map((prefix) => ({
      source: `/api/${prefix}/:path*`,
      destination: `${apiUrl}/${prefix}/:path*`,
    }));
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
