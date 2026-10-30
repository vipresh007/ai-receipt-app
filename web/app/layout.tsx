import type { Metadata, Viewport } from "next";
import { Auth0Provider } from "@auth0/nextjs-auth0";
import "./tokens.css";
import "./globals.css";
import { display, inter, mono } from "@/lib/fonts";
import { APP_STORE_ID, SITE_DESCRIPTION, SITE_TITLE, SITE_URL } from "@/lib/site";
import { Providers } from "./providers";

export const metadata: Metadata = {
  metadataBase: new URL(SITE_URL),
  title: { default: SITE_TITLE, template: "%s · Tally" },
  description: SITE_DESCRIPTION,
  applicationName: "Tally",
  publisher: "Data Eaver Inc.",
  alternates: { canonical: "/" },
  // Safari on iPhone shows an "Open in the App Store" banner.
  itunes: { appId: APP_STORE_ID },
  openGraph: {
    type: "website",
    siteName: "Tally",
    title: SITE_TITLE,
    description: SITE_DESCRIPTION,
    url: "/",
    locale: "en_CA",
  },
  twitter: { card: "summary_large_image", title: SITE_TITLE, description: SITE_DESCRIPTION },
};

export const viewport: Viewport = {
  // Lets the phone tab bar sit above the home indicator (safe-area insets).
  viewportFit: "cover",
  themeColor: [
    { media: "(prefers-color-scheme: light)", color: "#FAFAF9" },
    { media: "(prefers-color-scheme: dark)", color: "#0F0F10" },
  ],
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html
      lang="en"
      suppressHydrationWarning
      className={`${inter.variable} ${display.variable} ${mono.variable}`}
    >
      <body>
        <Auth0Provider>
          <Providers>{children}</Providers>
        </Auth0Provider>
      </body>
    </html>
  );
}
