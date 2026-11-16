import type { Metadata } from "next";
import { headers } from "next/headers";

import { APPEARANCE_BOOT_SCRIPT } from "@/lib/appearance";
import "./globals.css";

// Rendered per request, so Next can put proxy.ts's CSP nonce on its scripts:
// a page built ahead of time would carry none and be blocked.
export const dynamic = "force-dynamic";

export const metadata: Metadata = {
  title: {
    default: "Nebula Administration",
    template: "%s | Nebula Administration",
  },
  description: "Nebula VPN administration console",
};

export default async function RootLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  // The same nonce proxy.ts allows, so the appearance script may run.
  const nonce = (await headers()).get("x-nonce") ?? undefined;
  return (
    // The boot script sets data-look, data-accent and data-theme before
    // React hydrates; they are this browser's choice, not the server's.
    <html lang="en" suppressHydrationWarning>
      <head>
        <script
          nonce={nonce}
          dangerouslySetInnerHTML={{ __html: APPEARANCE_BOOT_SCRIPT }}
        />
      </head>
      <body>
        <a className="skip-link" href="#main-content">
          Skip to main content
        </a>
        {children}
      </body>
    </html>
  );
}
