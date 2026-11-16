import type { Metadata } from "next";
import { AppearancePanel } from "@/components/appearance-panel";

export const metadata: Metadata = { title: "Appearance" };

export default function AppearancePage() {
  return (
    <>
      <section className="page-heading" aria-labelledby="appearance-title">
        <h1 id="appearance-title">Appearance</h1>
        <p>
          How this panel looks in this browser. It does not change the app or
          what other admins see.
        </p>
      </section>
      <AppearancePanel />
    </>
  );
}
