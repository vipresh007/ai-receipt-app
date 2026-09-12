import type { Metadata, Viewport } from "next";
import { Auth0Provider } from "@auth0/nextjs-auth0";
import "./tokens.css";
import "./globals.css";
import { fraunces } from "@/lib/fonts";
import { Providers } from "./providers";

export const metadata: Metadata = {
  title: { default: "Tally", template: "%s · Tally" },
  description: "Snap a receipt. It tallies itself.",
  applicationName: "Tally",
};

export const viewport: Viewport = {
  themeColor: [
    { media: "(prefers-color-scheme: light)", color: "#FAFAF9" },
    { media: "(prefers-color-scheme: dark)", color: "#0F0F10" },
  ],
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" suppressHydrationWarning className={fraunces.variable}>
      <body>
        <Auth0Provider>
          <Providers>{children}</Providers>
        </Auth0Provider>
      </body>
    </html>
  );
}
