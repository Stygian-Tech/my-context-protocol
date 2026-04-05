import type { Metadata } from "next";
import "./globals.css";
import { Analytics } from "@vercel/analytics/react";
import { Providers } from "@/components/providers";
import { SkipToMainContent } from "@/components/a11y/skip-to-main";

export const metadata: Metadata = {
  title: "MyContextProtocol",
  description: "Hosted MCP endpoint for SKILL.md repos",
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
