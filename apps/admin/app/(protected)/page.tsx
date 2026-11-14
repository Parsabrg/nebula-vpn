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
        />
      </section>

      {showAttention && attention !== null ? (
        <section
          className="status-card attention"
          aria-labelledby="attention-title"
        >
          <h2 id="attention-title">Needs attention</h2>
          {attention.length === 0 ? (
            <p>Nothing needs attention.</p>
          ) : (
            <ul>
              {attention.map((item) => (
                <li key={`${item.href}:${item.text}`}>
                  <Link href={item.href}>
                    <span
                      className={`badge badge--${item.tone === "danger" ? "failed" : "pending"}`}
                    >
                      {item.tone === "danger" ? "Failing" : "Warning"}
                    </span>
                    {item.text}
                  </Link>
                </li>
              ))}
            </ul>
          )}
        </section>
      ) : null}
    </>
  );
}
