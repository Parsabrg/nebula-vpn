import type { Metadata } from "next";
import { LoginFlow } from "@/components/login-flow";

export const metadata: Metadata = {
  title: "Sign in",
};

export default async function LoginPage({
  searchParams,
}: {
  searchParams: Promise<{ reason?: string }>;
}) {
  const params = await searchParams;
  const expired = params.reason === "expired";

  return (
    // The design's sign-in: one card in the middle of the window.
    <main id="main-content" className="login-shell" tabIndex={-1}>
      <section className="login-card" aria-labelledby="login-title">
        <p className="login-card__brand">NEBULA</p>
        <h1 id="login-title">Administrator sign in</h1>
        {expired ? (
          <p role="status" className="notice notice--warning">
            Your session ended. Sign in again to continue.
          </p>
        ) : null}
        <LoginFlow />
      </section>
    </main>
  );
}
