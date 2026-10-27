import { auth0 } from "@/lib/auth0";
import { APP_STORE_URL, SITE_DESCRIPTION, SITE_URL } from "@/lib/site";

/** schema.org data for search engines and AI assistants: the app itself
 *  (with its App Store download), its publisher, and the FAQ shown on the page. */
const STRUCTURED_DATA = {
  "@context": "https://schema.org",
  "@graph": [
    {
      "@type": "Organization",
      "@id": "https://dataeaver.ca/#org",
      name: "Data Eaver Inc.",
      url: "https://dataeaver.ca/",
      email: "contact@dataeaver.ca",
    },
    {
      "@type": "MobileApplication",
      name: "Tally: Receipts & Spending",
      alternateName: "Tally",
      description: SITE_DESCRIPTION,
      url: SITE_URL,
      operatingSystem: "iOS 17 or later; any modern web browser",
      applicationCategory: "FinanceApplication",
      downloadUrl: APP_STORE_URL,
      installUrl: APP_STORE_URL,
      image: `${SITE_URL}/tally-icon-512.png`,
      offers: { "@type": "Offer", price: "0", priceCurrency: "CAD" },
      publisher: { "@id": "https://dataeaver.ca/#org" },
    },
    {
      "@type": "FAQPage",
      mainEntity: FAQ_ITEMS.map(({ q, a }) => ({
        "@type": "Question",
        name: q,
        acceptedAnswer: { "@type": "Answer", text: a },
      })),
    },
  ],
};
import {
  AuthErrorBanner,
  BottomCTA,
  FAQ,
  FAQ_ITEMS,
  Features,
  Figures,
  Hero,
  HowItWorks,
  Privacy,
  ReadsReceipts,
  SiteFooter,
  SiteHeader,
} from "@/components/landing";

export default async function Home({
  searchParams,
}: {
  searchParams: Promise<{ authError?: string }>;
}) {
  const { authError } = await searchParams;
  const session = await auth0.getSession();

  return (
    <div className="ledger min-h-dvh">
      <script
        type="application/ld+json"
        // Static, ours, and JSON-encoded: no user input reaches it.
        dangerouslySetInnerHTML={{ __html: JSON.stringify(STRUCTURED_DATA) }}
      />
      {authError && <AuthErrorBanner message={authError} />}
      <SiteHeader isSignedIn={!!session} />
      <main>
        <Hero />
        <Figures />
        <ReadsReceipts />
        <HowItWorks />
        <Features />
        <Privacy />
        <FAQ />
        <BottomCTA />
      </main>
      <SiteFooter />
    </div>
  );
}
