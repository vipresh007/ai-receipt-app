import type { Metadata } from "next";
import { LegalShell } from "@/components/legal-shell";

export const metadata: Metadata = {
  title: "Terms of Service",
  description: "The terms for using the Tally app and website, from Data Eaver Inc.",
  alternates: { canonical: "/terms" },
};

export default function TermsPage() {
  return <LegalShell file="terms" />;
}
