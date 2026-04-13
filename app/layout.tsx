import type { Metadata } from "next";
import "./globals.css";
import { Analytics } from "@vercel/analytics/react";
import { Providers } from "@/components/providers";
import { SkipToMainContent } from "@/components/a11y/skip-to-main";

const siteName = "MyContextProtocol";
const description = "Hosted MCP endpoint for SKILL.md repos";

/** Absolute URLs for Open Graph / Twitter require a resolved origin at build time. */
function metadataBase(): URL {
  const fromEnv = process.env.NEXT_PUBLIC_APP_URL?.trim();
  if (fromEnv) {
    const normalized = fromEnv.replace(/\/+$/, "");
    return new URL(`${normalized}/`);
  }
  if (process.env.VERCEL_URL) {
    return new URL(`https://${process.env.VERCEL_URL}/`);
  }
  return new URL("http://localhost:3000/");
}

export const metadata: Metadata = {
  metadataBase: metadataBase(),
  title: {
    default: siteName,
    template: `%s · ${siteName}`,
  },
  description,
  icons: {
    icon: "/favicon.ico",
    apple: "/apple-touch-icon.png",
  },
  openGraph: {
    title: siteName,
    description,
    siteName,
    type: "website",
    locale: "en_US",
    images: [{ url: "/og-image.png", alt: siteName }],
  },
  twitter: {
    card: "summary_large_image",
    title: siteName,
    description,
    images: ["/og-image.png"],
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en" suppressHydrationWarning>
      <body className="antialiased">
        <SkipToMainContent />
        <Providers>{children}</Providers>
        <Analytics />
      </body>
    </html>
  );
}
