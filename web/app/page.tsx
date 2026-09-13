import { auth0 } from "@/lib/auth0";
import {
  AuthErrorBanner,
  BottomCTA,
  Features,
  Hero,
  HowItWorks,
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
    <div className="min-h-dvh bg-bg text-text">
      {authError && <AuthErrorBanner message={authError} />}
      <SiteHeader isSignedIn={!!session} />
      <main>
        <Hero />
        <ReadsReceipts />
        <HowItWorks />
        <Features />
        <BottomCTA />
      </main>
      <SiteFooter />
    </div>
  );
}
