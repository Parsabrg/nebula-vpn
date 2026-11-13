import type { Metadata } from "next";
import Link from "next/link";
import {
  getTrafficSummary,
  getVpnServerReconciliation,
  listVpnServers,
  listReconciliationHistory,
} from "@/lib/topology";
import { ReconcileNowControl } from "@/components/reconcile-now-control";
import {
  ReconciliationSummary,
  ServerChecked,
  ServerHealthLive,
  ServerLiveFacts,
  ServerVerdict,
} from "@/components/server-health-live";
import { ServerNameControl } from "@/components/server-name-control";
import { ServerStateControl } from "@/components/server-state-control";
import { ServerForEveryone } from "@/components/everyone-access-button";
import { DataTable } from "@/components/data-table";
import { EmptyState } from "@/components/empty-state";
import { FilterBar } from "@/components/filter-bar";
import { PaginationControls } from "@/components/pagination-controls";

export const metadata: Metadata = {
  title: "Server health",
};

const OUTCOMES: Record<string, string> = {
  in_sync: "In sync",
  drift_detected: "Drift detected",
  repair_requested: "Repair requested",
  repair_succeeded: "Repair succeeded",
  repair_failed: "Repair failed",
  ambiguous: "Ambiguous",
};

const TRAFFIC_ENGINES = new Map([
  ["wireguard", "WireGuard"],
  ["xray", "Xray"],
  ["hysteria2", "Hysteria2"],
]);

interface HistorySearchParams {
  server_id?: string;
  target_id?: string;
  outcome?: string;
  offset?: string;
}

/** "3 min ago" against [now], with the exact time on hover. */
function Ago({ at, now }: { at: string; now: number }) {
  const seconds = Math.max(0, (now - new Date(at).getTime()) / 1000);
  const text =
    seconds < 90
      ? "just now"
      : seconds < 5400
        ? `${Math.round(seconds / 60)} min ago`
        : seconds < 172800
          ? `${Math.round(seconds / 3600)} h ago`
          : `${Math.round(seconds / 86400)} days ago`;
  return (
    <time dateTime={at} title={new Date(at).toISOString()}>
      {text}
    </time>
  );
}

/** "1.2 GB" to read, the exact byte count on hover: totals can pass the
    range a JavaScript number holds exactly, so the exact one is kept. */
function Bytes({ value }: { value: string }) {
  const exact = BigInt(value);
  const units = ["B", "KB", "MB", "GB", "TB", "PB", "EB", "ZB"];
  let unit = 0;
  while (unit < units.length - 1 && exact >= 1024n ** BigInt(unit + 1)) {
    unit += 1;
  }
  const shown =
    unit === 0
      ? `${exact} B`
      : `${(Number(exact / 1024n ** BigInt(unit - 1)) / 1024).toFixed(1)} ${units[unit]}`;
  return <span title={`${exact.toLocaleString("en-US")} bytes`}>{shown}</span>;
}

// One card per server rather than five wide tables of the same servers, and
// a sentence where a table of zeros said nothing (2026-10-29: "too crowded").
export default async function ServerHealthPage({
  searchParams,
}: {
  searchParams: Promise<HistorySearchParams>;
}) {
  const params = await searchParams;
  // Read once per render, so every "ago" on the page agrees.
  // eslint-disable-next-line react-hooks/purity -- a server render, once per request
  const now = Date.now();
  const parsedOffset = Number(params.offset ?? 0);
  const offset = Number.isFinite(parsedOffset)
    ? Math.max(0, Math.floor(parsedOffset))
    : 0;
  const filterValues = {
    server_id: params.server_id,
    target_id: params.target_id,
    outcome: params.outcome,
  };
  // The agents' own answers are not awaited here: they come from the
  // servers, and the slowest can take seconds. ServerHealthLive asks for
  // them once the page is on screen.
  const [servers, reconciliation, history, traffic] = await Promise.all([
    listVpnServers(),
    getVpnServerReconciliation(),
    listReconciliationHistory({
      ...(params.server_id ? { serverId: params.server_id } : {}),
      ...(params.target_id ? { targetId: params.target_id } : {}),
      ...(params.outcome ? { outcome: params.outcome } : {}),
      offset,
      limit: 25,
    }),
    getTrafficSummary(),
  ]);
  const outstanding = reconciliation.reduce(
    (sum, entry) =>
      sum +
      entry.pendingProvisions +
      entry.pendingRevocations +
      entry.failedRecords,
    0,
  );

  return (
    <ServerHealthLive>
      <section className="page-heading" aria-labelledby="server-health-title">
        <h1 id="server-health-title">Server health</h1>
        <p>Each server, whether it works, and what it has carried.</p>
        <p>
          <Link className="button button--primary" href="/server-health/add">
            Add server
          </Link>{" "}
          <Link className="button" href="/server-health/relays">
            Relays
          </Link>
          <Link className="button" href="/server-health/subscription-link">
            Subscription links
          </Link>
        </p>
      </section>

      {servers.length === 0 ? (
        <EmptyState title="No servers yet" status="not-connected">
          <p>
            A server appears here once its agent has enrolled with this control
            plane.
          </p>
        </EmptyState>
      ) : (
        <div className="server-cards">
          {servers.map((server) => {
            return (
              <article
                key={server.id}
                className="status-card server-card"
                aria-label={`Server ${server.displayName}`}
              >
                <header className="server-card__head">
                  <div>
                    <ServerNameControl
                      serverId={server.id}
                      code={server.code}
                      initialName={server.displayName}
                    />
                    <p className="server-card__host">{server.publicHost}</p>
                  </div>
                  <ServerStateControl
                    serverId={server.id}
                    code={server.code}
                    initialState={server.state}
                    relayOnly={server.relayOnly}
                  />
                </header>
                <ServerForEveryone
                  serverId={server.id}
                  name={server.displayName}
                />
                <ServerVerdict serverId={server.id} />
                <dl className="server-card__facts">
                  <ServerLiveFacts serverId={server.id} />
                  <dt>Devices</dt>
                  <dd>up to {server.maximumDevices}</dd>
                  <dt>Checked</dt>
                  <ServerChecked serverId={server.id} />
                </dl>
              </article>
            );
          })}
        </div>
      )}

      <section aria-labelledby="traffic-summary-title">
        <h2 id="traffic-summary-title">Traffic</h2>
        <p className="section-note">
          Totals since install, from the servers&apos; own counters.
        </p>
        <DataTable
          caption="Traffic by engine"
          headers={["Engine", "Received", "Sent", "Total", "Last counted"]}
          emptyMessage="No traffic has been counted yet."
          rows={traffic.map((item) => ({
            key: item.protocol,
            cells: [
              TRAFFIC_ENGINES.get(item.protocol) ?? item.protocol,
              <Bytes key="rx" value={item.rxBytes} />,
              <Bytes key="tx" value={item.txBytes} />,
              <Bytes key="total" value={item.totalBytes} />,
              item.newestCollectedAt === null ? (
                "Unknown"
              ) : (
                <Ago key="sample" at={item.newestCollectedAt} now={now} />
              ),
            ],
          }))}
        />
      </section>

      <section aria-labelledby="reconciliation-title">
        <h2 id="reconciliation-title">Reconciliation</h2>
        <p className="section-note">
          <ReconciliationSummary outstanding={outstanding} />
        </p>
        <p>
          <ReconcileNowControl />
        </p>
        {outstanding > 0 ? (
          <DataTable
            caption="Records not yet in sync"
            headers={[
              "Server",
              "Waiting to add",
              "Waiting to remove",
              "Failed",
            ]}
            emptyMessage="No VPN servers are configured."
            rows={reconciliation.map((entry) => ({
              key: entry.serverId,
              cells: [
                entry.code,
                entry.pendingProvisions,
                entry.pendingRevocations,
                entry.failedRecords,
              ],
            }))}
          />
        ) : null}
      </section>

      <details
        className="history"
        open={Boolean(params.server_id || params.target_id || params.outcome)}
      >
        <summary id="reconciliation-history-title">
          Reconciliation history ({history.total})
        </summary>
        <FilterBar
          fields={[
            {
              name: "server_id",
              label: "Server",
              type: "select",
              options: servers.map((server) => ({
                value: server.id,
                label: server.code,
              })),
            },
            {
              name: "outcome",
              label: "Outcome",
              type: "select",
              options: Object.entries(OUTCOMES).map(([value, label]) => ({
                value,
                label,
              })),
            },
            { name: "target_id", label: "Target ID", type: "text" },
          ]}
          values={filterValues}
        />
        <DataTable
          caption="Reconciliation checks"
          headers={[
            "Checked",
            "Server",
            "Target",
            "Desired generation",
            "Observed generation",
            "Outcome",
            "Error code",
            "Action",
          ]}
          emptyMessage="No reconciliation checks match these filters."
          rows={history.items.map((item) => ({
            key: item.id,
            cells: [
              <Ago key="time" at={item.checkedAt} now={now} />,
              item.serverCode,
              <Link
                key="target"
                href={`/server-health?${new URLSearchParams({ server_id: item.serverId, target_id: item.targetId })}`}
              >
                {item.targetKind} ({item.targetId})
              </Link>,
              item.desiredGeneration,
              item.observedGeneration ?? "Unknown",
              OUTCOMES[item.outcome] ?? item.outcome,
              item.errorCode ?? "Unknown",
              // Only where an operator has something to act on.
              item.outcome === "ambiguous" ||
              item.outcome === "repair_failed" ? (
                <ReconcileNowControl key="action" targetId={item.targetId} />
              ) : (
                ""
              ),
            ],
          }))}
        />
        <PaginationControls
          total={history.total}
          limit={history.limit}
          offset={history.offset}
          basePath="/server-health"
          searchParams={filterValues}
        />
      </details>
    </ServerHealthLive>
  );
}
