import type { Metadata } from "next";
import { DataTable } from "@/components/data-table";
import { RecoveryCodesRotate } from "@/components/recovery-codes-rotate";
import {
  ChangeOwnPassword,
  OwnPasskeys,
  ReplaceOwnAuthenticator,
} from "@/components/own-sign-in";
import { listPasskeys } from "@/lib/passkeys";
import { getSecurityStatus, type CheckStatus } from "@/lib/security";

export const metadata: Metadata = {
  title: "Security",
};

const STATUS_LABEL: Record<CheckStatus, string> = {
  ok: "OK",
  warning: "Warning",
  failing: "Failing",
  unknown: "Unknown",
};

export default async function SecurityPage() {
  const [checks, passkeys] = await Promise.all([
    getSecurityStatus(),
    listPasskeys(),
  ]);
  const attention = checks.filter(
    (check) => check.status === "failing" || check.status === "warning",
  ).length;

  return (
    <>
      <section className="page-heading" aria-labelledby="security-title">
        <h1 id="security-title">Security</h1>
        <p>
          What the control plane can observe for itself, read when this page
          loaded. Anything it cannot observe says Unknown, never OK. CI scan
          results are on GitHub and are not repeated here.
        </p>
        <p role="status">
          {attention === 0
            ? "Nothing needs attention."
            : `${attention} ${attention === 1 ? "item needs" : "items need"} attention.`}
        </p>
      </section>

      <DataTable
        caption="Security checks"
        headers={["Check", "Status", "Detail", "Evidence (UTC)"]}
        emptyMessage="No checks were returned."
        rows={checks.map((check) => ({
          key: check.key,
          cells: [
            check.label,
            <span key="status" className={`badge badge--check-${check.status}`}>
              {STATUS_LABEL[check.status]}
            </span>,
            check.detail,
            check.observedAt
              ? new Date(check.observedAt)
                  .toISOString()
                  .replace("T", " ")
                  .slice(0, 19)
              : "—",
          ],
        }))}
      />

      <section className="status-card" aria-labelledby="recovery-title">
        <h2 id="recovery-title">Your recovery codes</h2>
        <RecoveryCodesRotate />
      </section>

      <section className="status-card" aria-labelledby="own-password-title">
        <h2 id="own-password-title">Your password</h2>
        <ChangeOwnPassword />
      </section>

      <section className="status-card" aria-labelledby="own-mfa-title">
        <h2 id="own-mfa-title">Your authenticator</h2>
        <ReplaceOwnAuthenticator />
      </section>

      <section className="status-card" aria-labelledby="own-passkeys-title">
        <h2 id="own-passkeys-title">Your passkeys</h2>
        <p>
          Sign in with a passkey (fingerprint, face, or a security key) in place
          of the 6-digit code. Changes that need a fresh code still ask for one.
        </p>
        <OwnPasskeys initial={passkeys} />
      </section>
    </>
  );
}
