import { auth0 } from "@/lib/auth0";
import {
  AuthErrorBanner,
  BottomCTA,
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
      {authError && <AuthErrorBanner message={authError} />}
      <SiteHeader isSignedIn={!!session} />
      <main>
        <Hero />
        <Figures />
        <ReadsReceipts />
        <HowItWorks />
        <Features />
        <Privacy />
        <BottomCTA />
      </main>
      <SiteFooter />
    </div>
  );
}
