"use client";

import { useCallback, useEffect, useState } from "react";
import type { ActionResult } from "@/lib/api/action-result";
import { checkDnsRecords, type DnsRecordStatus } from "@/lib/topology-actions";
import { CopyButton } from "./copy-button";

const PURPOSE: Record<DnsRecordStatus["purpose"], string> = {
  "control-plane": "Panel and API",
  server: "Server",
  cdn: "CDN route",
  "dns-tunnel": "DNS tunnel",
};

/**
 * The deployment's DNS records, each looked up live: what is missing or
 * wrong first, copyable for the DNS provider. DNS changes take minutes, so
 * "Check again" asks once more.
 */
export function DnsRecordsView() {
  const [items, setItems] = useState<DnsRecordStatus[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(true);

  const show = useCallback((result: ActionResult<DnsRecordStatus[]>) => {
    setBusy(false);
    if (result.ok) {
      setItems(result.data);
      setError(null);
    } else {
      setError(result.message);
    }
  }, []);

  useEffect(() => {
    void checkDnsRecords().then(show);
  }, [show]);

  const run = () => {
    setBusy(true);
    void checkDnsRecords().then(show);
  };

  const toFix = (items ?? []).filter((item) => !item.ok);
  const asText = toFix
    .map(
      (r) =>
        `${r.name}  ${r.type}  ${r.value}  ${r.proxied ? "proxied" : "DNS only"}`,
    )
    .join("\n");

  return (
    <section className="panel" aria-live="polite" aria-busy={busy}>
      {error && (
        <p className="field__error" role="alert">
          {error}
        </p>
      )}
      {items && (
        <p className="field__help">
          {items.length === 0
            ? "This deployment uses no names of its own."
            : toFix.length === 0
              ? "Every record is in place."
              : `${toFix.length} of ${items.length} need fixing at your DNS provider.`}
        </p>
      )}
      {items && items.length > 0 && (
        <table className="compact-table">
          <thead>
            <tr>
              <th>State</th>
              <th>Name</th>
              <th>Type</th>
              <th>Points at</th>
              <th>Proxy</th>
              <th>For</th>
              <th>Now</th>
            </tr>
          </thead>
          <tbody>
            {[...toFix, ...items.filter((item) => item.ok)].map((r) => (
              <tr key={`${r.name}-${r.type}`}>
                <td className={r.ok ? "is-ok" : "is-bad"}>
                  {r.ok ? "✓ OK" : "✗ Fix"}
                </td>
                <td className="mono">{r.name}</td>
                <td>{r.type}</td>
                <td className="mono">{r.value}</td>
                <td>{r.proxied ? "Proxied" : "DNS only"}</td>
                <td>{PURPOSE[r.purpose]}</td>
                <td>{r.detail}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
      <div className="button-row">
        {toFix.length > 0 && (
          <CopyButton text={asText} label="Copy records to fix" />
        )}
        <button type="button" className="button" disabled={busy} onClick={run}>
          {busy ? "Checking…" : "Check again"}
        </button>
      </div>
    </section>
  );
}
