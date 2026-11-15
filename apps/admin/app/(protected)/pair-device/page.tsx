import type { Metadata } from "next";
import { getDevicePairing } from "@/lib/pairing";
import { CopyButton } from "@/components/copy-button";

export const metadata: Metadata = {
  title: "Pair a device",
};

export default async function PairDevicePage() {
  const pairing = await getDevicePairing();

  return (
    <>
      <section className="page-heading" aria-labelledby="pair-device-title">
        <h1 id="pair-device-title">Pair a device</h1>
        <p>
          The Nebula app has no server built in. On first launch it asks for
          this link, then checks that the server it reaches is this deployment
          before anyone signs in.
        </p>
      </section>

      <section className="status-card" aria-labelledby="pair-device-qr">
        <h2 id="pair-device-qr">Scan or share</h2>
        <p className="status-card__desc">
          Send the link to the person, or let them scan the code. Paste it into
          the app&apos;s first screen.
        </p>
        {/* The design's pair: the code at the left, the link beside it. */}
        <div className="pair-share">
          {/* eslint-disable-next-line @next/next/no-img-element -- an inline data URL, nothing to optimise */}
          <img
            className="pair-share__qr"
            src={pairing.qrImage}
            alt="QR code of the pairing link"
            width={168}
            height={168}
          />
          <div className="pair-share__link">
            <span className="kv-label">Pairing link</span>
            <span className="numeric">{pairing.link}</span>
          </div>
        </div>
        <div className="pair-share__copy">
          <CopyButton text={pairing.link} label="Copy link" primary />
        </div>
      </section>

      <section className="status-card" aria-labelledby="pair-device-trust">
        <h2 id="pair-device-trust">What the link proves</h2>
        <dl className="kv-grid">
          <div>
            <dt>Deployment</dt>
            <dd className="numeric">{pairing.deploymentId}</dd>
          </div>
          <div>
            <dt>Certificate authority</dt>
            {/* Short, as the design shows it; the whole of it on hover and
                in the sentence below. */}
            <dd className="numeric" title={pairing.caSha256 ?? undefined}>
              {pairing.caSha256
                ? `SHA-256 ${pairing.caSha256.slice(0, 4)} ${pairing.caSha256.slice(4, 8)} ${pairing.caSha256.slice(8, 12)} … ${pairing.caSha256.slice(-4)}`
                : "Public"}
            </dd>
          </div>
        </dl>
        <p className="status-card__desc">
          {pairing.caSha256 ? (
            <>
              This installation issues its own certificate. The app trusts only
              the CA with SHA-256 <code>{pairing.caSha256}</code>, so share the
              link itself, not just the address.
            </>
          ) : (
            <>
              A publicly trusted certificate. The app can also be paired by
              typing this server&apos;s address.
            </>
          )}
        </p>
        <p className="status-card__desc">
          The link holds no password or account. It tells the app which server
          to trust. Accounts are still requested and approved as before.
        </p>
      </section>
    </>
  );
}
