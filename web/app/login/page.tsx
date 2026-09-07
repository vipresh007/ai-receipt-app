import { AuthForm } from "@/components/auth-form";

export const dynamic = "force-dynamic";

export default function LoginPage() {
  return (
    <main className="grid min-h-dvh place-items-center p-lg">
      <AuthForm mode="login" />
    </main>
  );
}
