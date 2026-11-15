import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { label } from "@/lib/labels";
import { getUserDetail } from "@/lib/users";
import { listUserAssignments, listUserPermissions } from "@/lib/access";
import { listProtocolProfiles, listVpnServers } from "@/lib/topology";
import { UserAccountActions } from "@/components/user-account-actions";
import { UserIdentityControl } from "@/components/user-identity-control";
import { UserStatusControl } from "@/components/user-status-control";
import { DeviceRow } from "@/components/device-row";
import { SessionRow } from "@/components/session-row";
import { PermissionsPanel } from "@/components/permissions-panel";
import { AssignmentsPanel } from "@/components/assignments-panel";
import { AccessReadiness } from "@/components/access-readiness";
import { DeviceLimitControl } from "@/components/device-limit-control";
import { DnsProfileControl } from "@/components/dns-profile-control";
import { ExpiryControl } from "@/components/expiry-control";
import { TrafficAllowancePanel } from "@/components/traffic-allowance-panel";
import { LocalTime } from "@/components/local-time";

export const metadata: Metadata = {
  title: "User detail",
};

/** The design's tabs, each its own address so it can be linked to and the
 * back button returns to it. */
const TABS = [
  ["account", "Account"],
  ["devices", "Devices"],
  ["sessions", "Sessions"],
  ["access", "Protocols & servers"],
  ["traffic", "Traffic"],
] as const;
type Tab = (typeof TABS)[number][0];

export default async function UserDetailPage({
  params,
  searchParams,
}: {
  params: Promise<{ userId: string }>;
  searchParams?: Promise<{ tab?: string }>;
}) {
  const { userId } = await params;
  const asked = (await searchParams)?.tab;
  const tab: Tab = TABS.some(([key]) => key === asked)
    ? (asked as Tab)
    : "account";
  const detail = await getUserDetail(userId);
  if (!detail) {
    notFound();
  }
  const { user, devices, sessions, traffic } = detail;
  const [permissions, assignments, profiles, servers] = await Promise.all([
    listUserPermissions(user.id),
    listUserAssignments(user.id),
    listProtocolProfiles(),
    listVpnServers(),
  ]);

  const grantedProfileIds = new Set(
    permissions
      .filter((p) => p.state === "enabled")
      .map((p) => p.protocolProfileId),
  );
  const assignedServerIds = new Set(
    assignments.filter((a) => a.state === "active").map((a) => a.vpnServerId),
  );

  const counts: Partial<Record<Tab, number>> = {
    devices: devices.length,
    sessions: sessions.length,
  };

  return (
    <>
      <Link className="crumb" href="/users">
        <span className="icon" aria-hidden="true">
          arrow_back
        </span>
        Users
      </Link>
      <section className="page-heading" aria-labelledby="user-detail-title">
        <h1 id="user-detail-title">
          {user.email}
          <span className={`badge badge--${user.state}`}>
            {label(user.state)}
          </span>
        </h1>
        <p>{user.username ? `Username ${user.username}` : "No username set"}</p>
      </section>

      <nav className="tabs" aria-label="User sections">
        {TABS.map(([key, name]) => (
          <Link
            key={key}
            href={key === "account" ? `/users/${user.id}` : `?tab=${key}`}
            aria-current={tab === key ? "page" : undefined}
          >
            {name}
            {counts[key] ? (
              <span className="count-badge">{counts[key]}</span>
            ) : null}
          </Link>
        ))}
      </nav>

      {tab === "account" ? (
        <>
          <section className="status-card" aria-labelledby="details-title">
            <div className="status-card__head">
              <h2 id="details-title">Details</h2>
              <UserIdentityControl
                userId={user.id}
                email={user.email}
                username={user.username}
              />
            </div>
            <dl className="kv-grid">
              <div>
                <dt>Email</dt>
                <dd>{user.email}</dd>
              </div>
              <div>
                <dt>Username</dt>
                <dd>{user.username ?? "—"}</dd>
              </div>
              <div>
                <dt>Created</dt>
                <dd>
                  <LocalTime value={user.createdAt} dateOnly />
                </dd>
              </div>
              <div>
                <dt>Activated</dt>
                <dd>
                  {user.activatedAt ? (
                    <LocalTime value={user.activatedAt} dateOnly />
                  ) : (
                    "—"
                  )}
                </dd>
              </div>
              {user.disabledAt ? (
                <div>
                  <dt>Disabled</dt>
                  <dd>
                    <LocalTime value={user.disabledAt} dateOnly />
                  </dd>
                </div>
              ) : null}
            </dl>
          </section>

          <section className="status-card" aria-labelledby="expiry-title">
            <h2 id="expiry-title">When access ends</h2>
            <ExpiryControl userId={user.id} initialExpiresAt={user.expiresAt} />
          </section>

          <section className="status-card" aria-labelledby="limit-title">
            <h2 id="limit-title">Devices allowed at once</h2>
            <DeviceLimitControl
              userId={user.id}
              initialLimit={user.deviceLimit}
            />
          </section>

          <section className="status-card" aria-labelledby="dns-title">
            <h2 id="dns-title">DNS</h2>
            <DnsProfileControl
              userId={user.id}
              initialProfile={user.dnsProfile}
            />
          </section>

          <section className="status-card" aria-labelledby="state-title">
            <h2 id="state-title">Account</h2>
            <div className="user-actions">
              <UserStatusControl userId={user.id} initialState={user.state} />
              <UserAccountActions
                userId={user.id}
                email={user.email}
                state={user.state}
              />
            </div>
          </section>
        </>
      ) : null}

      {tab === "devices" ? (
        <section className="status-card" aria-labelledby="devices-title">
          <h2 id="devices-title">Devices</h2>
          {devices.length === 0 ? (
            <p role="status">This user has no devices.</p>
          ) : (
            <table
              className="data-table data-table--stack"
              aria-label="Devices"
            >
              <thead>
                <tr>
                  <th scope="col">Name</th>
                  <th scope="col">Platform</th>
                  <th scope="col">Client version</th>
                  <th scope="col">State</th>
                  <th scope="col">Online</th>
                  <th scope="col">DNS</th>
                  <th scope="col">Actions</th>
                </tr>
              </thead>
              <tbody>
                {devices.map((device) => (
                  <DeviceRow key={device.id} userId={user.id} device={device} />
                ))}
              </tbody>
            </table>
          )}
        </section>
      ) : null}

      {tab === "sessions" ? (
        <section className="status-card" aria-labelledby="sessions-title">
          <h2 id="sessions-title">Sessions</h2>
          {sessions.length === 0 ? (
            <p role="status">This user has no sessions.</p>
          ) : (
            <table
              className="data-table data-table--stack"
              aria-label="Sessions"
            >
              <thead>
                <tr>
                  <th scope="col">Device</th>
                  <th scope="col">State</th>
                  <th scope="col">Expires</th>
                  <th scope="col">Last seen</th>
                  <th scope="col">Actions</th>
                </tr>
              </thead>
              <tbody>
                {sessions.map((session) => (
                  <SessionRow
                    key={session.id}
                    userId={user.id}
                    session={session}
                  />
                ))}
              </tbody>
            </table>
          )}
        </section>
      ) : null}

      {tab === "access" || tab === "account" ? (
        <AccessReadiness
          userId={user.id}
          hasProtocol={grantedProfileIds.size > 0}
          hasServer={assignedServerIds.size > 0}
          missingProfileIds={profiles
            .filter((profile) => !grantedProfileIds.has(profile.id))
            .map((profile) => profile.id)}
          missingServerIds={servers
            .filter(
              (server) =>
                server.state === "active" && !assignedServerIds.has(server.id),
            )
            .map((server) => server.id)}
        />
      ) : null}

      {tab === "access" ? (
        <>
          <section className="status-card" aria-labelledby="permissions-title">
            <h2 id="permissions-title">Permissions</h2>
            <PermissionsPanel
              key={`p${grantedProfileIds.size}`}
              userId={user.id}
              initialPermissions={permissions}
              profiles={profiles}
            />
          </section>

          <section className="status-card" aria-labelledby="assignments-title">
            <h2 id="assignments-title">Assignments</h2>
            <AssignmentsPanel
              key={`a${assignedServerIds.size}`}
              userId={user.id}
              initialAssignments={assignments}
              servers={servers}
            />
          </section>
        </>
      ) : null}

      {tab === "traffic" ? (
        <section className="status-card" aria-labelledby="traffic-title">
          <h2 id="traffic-title">Traffic allowance</h2>
          <TrafficAllowancePanel userId={user.id} initialAllowance={traffic} />
        </section>
      ) : null}
    </>
  );
}
