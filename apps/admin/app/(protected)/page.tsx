import Link from "next/link";
import { listPendingAccountRequests } from "@/lib/account-requests";
import {
  attentionItems,
  needsAttentionEnabled,
  type AttentionItem,
} from "@/lib/attention";
import { listEmailDeliveries } from "@/lib/email-deliveries";
import { getSecurityStatus } from "@/lib/security";
import { getVpnServerHealth, listVpnServers } from "@/lib/topology";
import { listUsers } from "@/lib/users";
import { DataTable } from "@/components/data-table";
import { StatTile } from "@/components/stat-tile";

/** The card's sources, each allowed to fail without taking the page down. */
async function loadAttention(): Promise<AttentionItem[] | null> {
  const [health, checks, failed] = await Promise.allSettled([
    getVpnServerHealth(),
    getSecurityStatus(),
    listEmailDeliveries({ state: "failed", limit: 1 }),
  ]);
  if (
    health.status === "rejected" &&
    checks.status === "rejected" &&
    failed.status === "rejected"
  ) {
    return null;
  }
  return attentionItems(
    health.status === "fulfilled" ? health.value : [],
    checks.status === "fulfilled" ? checks.value : [],
    failed.status === "fulfilled" ? failed.value.total : 0,
  );
}

export default async function OverviewPage() {
  const showAttention = needsAttentionEnabled();
  const [pendingRequests, totalUsers, activeUsers, servers, attention] =
    await Promise.all([
      listPendingAccountRequests(),
      listUsers({ limit: 1 }),
      listUsers({ state: "active", limit: 1 }),
      listVpnServers(),
      showAttention ? loadAttention() : Promise.resolve(null),
    ]);

  // From the same checks as Needs attention, so the two agree.
  const serversNeedingAttention =
    attention?.filter((item) => item.where === "Servers").length ?? 0;

  return (
    <>
      <section className="page-heading" aria-labelledby="overview-title">
        <h1 id="overview-title">Overview</h1>
        <p>Current state of account requests, users, and VPN capacity.</p>
      </section>

      <section className="status-grid" aria-label="Administration summary">
        <StatTile
          label={
            pendingRequests.length === 1
              ? "Pending request"
              : "Pending requests"
          }
          value={pendingRequests.length}
          href="/requests"
          note={
            pendingRequests.length > 0 ? "Waiting for a decision" : undefined
          }
        />
        <StatTile
          label={activeUsers.total === 1 ? "Active user" : "Active users"}
          value={activeUsers.total}
          href="/users?state=active"
        />
        <StatTile
          label={totalUsers.total === 1 ? "User in total" : "Users in total"}
          value={totalUsers.total}
          href="/users"
        />
        <StatTile
          label={servers.length === 1 ? "VPN server" : "VPN servers"}
          value={servers.length}
          href="/server-health"
          note={
            serversNeedingAttention > 0
              ? `${serversNeedingAttention} ${serversNeedingAttention === 1 ? "needs" : "need"} attention`
              : undefined
          }
        />
      </section>

      {showAttention && attention !== null ? (
        <section
          className="status-card attention"
          aria-labelledby="attention-title"
        >
          <h2 id="attention-title">Needs attention</h2>
          <p className="status-card__desc">
            Collected from the Servers, Security and Email pages, where each one
            is fixed.
          </p>
          {attention.length === 0 ? (
            <p>Nothing needs attention.</p>
          ) : (
            <DataTable
              caption="Needs attention"
              headers={["Item", "Where", ""]}
              emptyMessage="Nothing needs attention."
              rows={attention.map((item) => ({
                key: `${item.href}:${item.text}`,
                cells: [
                  <strong key="item">{item.text}</strong>,
                  <span key="where" className="muted">
                    {item.where}
                  </span>,
                  <Link
                    key="open"
                    className="button button--small"
                    href={item.href}
                    aria-label={`Open ${item.where}: ${item.text}`}
                  >
                    Open
                  </Link>,
                ],
              }))}
            />
          )}
        </section>
      ) : null}
    </>
  );
}
