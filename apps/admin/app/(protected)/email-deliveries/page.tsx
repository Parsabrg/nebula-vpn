import type { Metadata } from "next";
import Link from "next/link";
import { listEmailDeliveries } from "@/lib/email-deliveries";
import { DataTable } from "@/components/data-table";
import { FilterBar, type FilterField } from "@/components/filter-bar";
import { PaginationControls } from "@/components/pagination-controls";
import { LocalTime } from "@/components/local-time";
import { codeOptions, label } from "@/lib/labels";

export const metadata: Metadata = {
  title: "Email deliveries",
};

const PAGE_SIZE = 25;

/** Mirrors the closed vocabulary in services/api/src/nebula_api/models/operations.py. */
const STATES = ["pending", "sending", "sent", "failed", "cancelled"];
const TEMPLATE_CODES = [
  "account_request_review",
  "user_activation",
  "password_reset",
  "request_rejected",
];
const SUBJECT_KINDS = ["account_request", "user", "admin"];

const FILTER_FIELDS: FilterField[] = [
  {
    name: "state",
    label: "State",
    type: "select",
    options: codeOptions(STATES),
  },
  {
    name: "template_code",
    label: "Template",
    type: "select",
    options: codeOptions(TEMPLATE_CODES),
  },
  {
    name: "subject_kind",
    label: "Subject kind",
    type: "select",
    options: codeOptions(SUBJECT_KINDS),
  },
];

interface EmailDeliverySearchParams {
  state?: string;
  template_code?: string;
  subject_kind?: string;
  offset?: string;
}

/** Each template's subject line, as the worker sends it
 * (services/worker/src/nebula_worker/templates.py). */
const SUBJECTS: Record<string, string> = {
  account_request_review: "New Nebula account request pending review",
  user_activation: "Activate your Nebula account",
  password_reset: "Reset your Nebula password",
  request_rejected: "Your Nebula account request was not approved",
};

export default async function EmailDeliveriesPage({
  searchParams,
}: {
  searchParams: Promise<EmailDeliverySearchParams>;
}) {
  const params = await searchParams;
  const offset = Number(params.offset ?? 0) || 0;
  const filterValues = {
    state: params.state,
    template_code: params.template_code,
    subject_kind: params.subject_kind,
  };

  const page = await listEmailDeliveries({
    ...(params.state ? { state: params.state } : {}),
    ...(params.template_code ? { templateCode: params.template_code } : {}),
    ...(params.subject_kind ? { subjectKind: params.subject_kind } : {}),
    limit: PAGE_SIZE,
    offset,
  });

  return (
    <>
      <section
        className="page-heading"
        aria-labelledby="email-deliveries-title"
      >
        <h1 id="email-deliveries-title">Email deliveries</h1>
        <p>Delivery status for account-request and user emails.</p>
      </section>

      <FilterBar fields={FILTER_FIELDS} values={filterValues} />

      <section className="status-card" aria-labelledby="emails-title">
        <h2 id="emails-title">
          Emails
          <span className="count-badge">{page.total}</span>
        </h2>
        <DataTable
          caption="Email deliveries"
          headers={[
            "Recipient",
            "Subject",
            "Template",
            "State",
            "Attempts",
            "Sent",
            "Result",
          ]}
          numeric={[4]}
          emptyMessage="No email deliveries match these filters."
          rows={page.items.map((item) => ({
            key: item.id,
            cells: [
              // The recipient leads to the user the email was about.
              item.subjectKind === "user" ? (
                <Link key="to" href={`/users/${item.subjectId}`}>
                  {item.recipientAddress}
                </Link>
              ) : (
                <strong key="to">{item.recipientAddress}</strong>
              ),
              SUBJECTS[item.templateCode] ?? "—",
              <span key="template" className="muted">
                {label(item.templateCode)}
              </span>,
              <span key="state" className={`badge badge--${item.state}`}>
                {label(item.state)}
              </span>,
              <span key="attempts" className="numeric">
                {item.attemptCount}
              </span>,
              item.sentAt ? (
                <span key="sent" className="muted">
                  <LocalTime value={item.sentAt} />
                </span>
              ) : (
                "—"
              ),
              item.resultCode ? label(item.resultCode) : "—",
            ],
          }))}
        />

        <PaginationControls
          total={page.total}
          limit={page.limit}
          offset={page.offset}
          basePath="/email-deliveries"
          searchParams={filterValues}
        />
      </section>
    </>
  );
}
