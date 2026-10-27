import type { Metadata } from "next";
import { LegalShell } from "@/components/legal-shell";

export const metadata: Metadata = {
  title: "Privacy Policy",
  description: "How Tally collects, uses and protects your receipts and account data.",
  alternates: { canonical: "/privacy" },
};

export default function PrivacyPage() {
  return <LegalShell file="privacy" />;
}
