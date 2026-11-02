import type { Metadata } from "next";
import Link from "next/link";
import { listAuditLog } from "@/lib/audit-log";
import { DataTable } from "@/components/data-table";
import { FilterBar, type FilterField } from "@/components/filter-bar";
import { PaginationControls } from "@/components/pagination-controls";
import { LocalTime } from "@/components/local-time";
import { codeOptions, label } from "@/lib/labels";

export const metadata: Metadata = {
  title: "Audit log",
};

const PAGE_SIZE = 25;

/** Mirrors the closed vocabulary in services/api/src/nebula_api/models/operations.py. */
const ACTOR_KINDS = [
  "user",
  "admin",
  "anonymous",
  "system",
  "worker",
  "agent",
  "bootstrap",
];
const TARGET_KINDS = [
  "user",
  "admin",
  "auth_attempt",
  "user_session",
  "admin_session",
  "refresh_token",
  "password_reset_token",
  "admin_totp_credential",
  "admin_recovery_code",
  "device",
  "account_request",
  "protocol_profile",
  "permission",
  "vpn_server",
  "server_capability",
  "assignment",
  "device_credential",
  "wireguard_peer",
  "xray_client",
  "agent_operation",
  "setting",
  "email_delivery",
];
const EVENT_CODES = [
  "admin_seeded",
  "identity_state_changed",
  "device_state_changed",
  "account_request_changed",
  "profile_changed",
  "permission_changed",
  "server_changed",
  "capability_changed",
  "assignment_changed",
  "credential_changed",
  "peer_changed",
  "operation_changed",
  "setting_changed",
  "email_delivery_changed",
  "user_authenticated",
  "admin_authenticated",
  "refresh_rotated",
  "refresh_reuse_detected",
  "session_revoked",
  "password_changed",
  "password_reset_requested",
  "password_reset_consumed",
  "admin_mfa_changed",
  "admin_mfa_challenged",
  "admin_recovery_code_used",
  "auth_lockout_changed",
  "auth_rate_limited",
  "csrf_validation",
];
const OUTCOMES = ["succeeded", "failed", "denied"];

const FILTER_FIELDS: FilterField[] = [
  {
    name: "actor_kind",
    label: "Actor kind",
    type: "select",
    options: codeOptions(ACTOR_KINDS),
  },
  {
    name: "target_kind",
    label: "Target kind",
    type: "select",
    options: codeOptions(TARGET_KINDS),
  },
  {
    name: "event_code",
    label: "Event",
    type: "select",
    options: codeOptions(EVENT_CODES),
  },
  {
    name: "outcome",
    label: "Outcome",
    type: "select",
    options: codeOptions(OUTCOMES),
  },
];

/** Ids are long; the first block tells rows apart. */
function shortId(id: string): string {
  return id.slice(0, 8);
}

/** The target, linked when the panel has a page for it. */
function Target({
  kind,
  id,
  name,
}: {
  kind: string;
  id: string;
  name: string | null;
}) {
  const text = name ?? `${label(kind)} ${shortId(id)}`;
  if (kind === "user") return <Link href={`/users/${id}`}>{text}</Link>;
  if (kind === "vpn_server") return <Link href="/server-health">{text}</Link>;
  return <span title={id}>{text}</span>;
}

interface AuditLogSearchParams {
  actor_kind?: string;
  target_kind?: string;
  event_code?: string;
  outcome?: string;
  offset?: string;
}

export default async function AuditLogPage({
  searchParams,
}: {
  searchParams: Promise<AuditLogSearchParams>;
}) {
  const params = await searchParams;
  const offset = Number(params.offset ?? 0) || 0;
  const filterValues = {
    actor_kind: params.actor_kind,
    target_kind: params.target_kind,
    event_code: params.event_code,
    outcome: params.outcome,
  };

  const page = await listAuditLog({
    ...(params.actor_kind ? { actorKind: params.actor_kind } : {}),
    ...(params.target_kind ? { targetKind: params.target_kind } : {}),
    ...(params.event_code ? { eventCode: params.event_code } : {}),
    ...(params.outcome ? { outcome: params.outcome } : {}),
    limit: PAGE_SIZE,
    offset,
  });

  return (
    <>
      <section className="page-heading" aria-labelledby="audit-log-title">
        <h1 id="audit-log-title">Audit log</h1>
        <p>Append-only record of administrator and system actions.</p>
        <p>
          <a
            className="button button--secondary"
            href="/api/admin/audit-log/export"
            download
          >
            Export as a hash chain
          </a>{" "}
          Keep exports off this server; <code>nebula-api audit-verify</code>{" "}
          shows whether a later one still contains an earlier one unchanged.
        </p>
      </section>

      <FilterBar fields={FILTER_FIELDS} values={filterValues} />

      <DataTable
        caption="Audit events"
        headers={["Recorded", "Actor", "Target", "Event", "Outcome", "Reason"]}
        emptyMessage="No audit events match these filters."
        rows={page.items.map((item) => ({
          key: item.id,
          cells: [
            <LocalTime key="time-1" value={item.recordedAt} />,
            item.actorId
              ? (item.actorName ??
                `${label(item.actorKind)} ${shortId(item.actorId)}`)
              : label(item.actorKind),
            <Target
              key="target"
              kind={item.targetKind}
              id={item.targetId}
              name={item.targetName}
            />,
            label(item.eventCode),
            label(item.outcome),
            item.reasonCode ? label(item.reasonCode) : "—",
          ],
        }))}
      />

      <PaginationControls
        total={page.total}
        limit={page.limit}
        offset={page.offset}
        basePath="/audit-log"
        searchParams={filterValues}
      />
    </>
  );
}
