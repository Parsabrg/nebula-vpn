"use client";

import { useCallback, useEffect, useState } from "react";
import type { ActionResult } from "@/lib/api/action-result";
import { checkDnsTunnel, type DnsTunnelStatus } from "@/lib/topology-actions";
import { CopyButton } from "./copy-button";

/**
 * A server's DNS tunnel, as it stands: the records to add at the DNS
 * provider (copyable) and whether the name already reaches the server.
 * Asked when shown and again on "Check again"; DNS changes take minutes.
 */
export function DnsTunnelStatusView({ serverId }: { serverId: string }) {
  const [status, setStatus] = useState<DnsTunnelStatus | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(true);

  const show = useCallback((result: ActionResult<DnsTunnelStatus>) => {
    setBusy(false);
    if (result.ok) {
      setStatus(result.data);
      setError(null);
    } else {
      setError(result.message);
    }
  }, []);

  const run = () => {
    setBusy(true);
    void checkDnsTunnel(serverId).then(show);
  };

  useEffect(() => {
    void checkDnsTunnel(serverId).then(show);
  }, [serverId, show]);

  const records = status?.records ?? [];
  const asText = records
    .map((r) => `${r.name}  ${r.type}  ${r.value}`)
    .join("\n");
  const working = status?.checks.every((check) => check.ok) ?? false;

  return (
    <div className="dns-tunnel-status" aria-live="polite">
      {error && (
        <p className="field__error" role="alert">
          {error}
        </p>
      )}
      {status && (
        <>
          <p className="field__help">
            {working
              ? "Working: apps on this server can use the DNS tunnel."
              : 'Add these records at your DNS provider, both "DNS only" (not proxied), then check again:'}
          </p>
          {!working && (
            <table className="compact-table">
              <thead>
                <tr>
                  <th>Name</th>
                  <th>Type</th>
                  <th>Value</th>
                </tr>
              </thead>
              <tbody>
                {records.map((r) => (
                  <tr key={`${r.name}-${r.type}`}>
                    <td className="mono">{r.name}</td>
                    <td>{r.type}</td>
                    <td className="mono">{r.value}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
          <ul className="check-list">
            {status.checks.map((check) => (
              <li key={check.key} className={check.ok ? "is-ok" : "is-bad"}>
                {check.ok ? "✓" : "✗"} {check.detail}
              </li>
            ))}
          </ul>
        </>
      )}
      <div className="button-row">
        {!working && records.length > 0 && (
          <CopyButton text={asText} label="Copy records" />
        )}
        <button
          type="button"
          className="button"
          disabled={busy}
          onClick={() => void run()}
        >
          {busy ? "Checking…" : "Check again"}
        </button>
      </div>
    </div>
  );
}
