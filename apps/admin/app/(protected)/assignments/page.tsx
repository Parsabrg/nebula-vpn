import type { Metadata } from "next";
import Link from "next/link";
import { listAllAssignments } from "@/lib/access";
import { DataTable } from "@/components/data-table";
import { EmptyState } from "@/components/empty-state";
import { PaginationControls } from "@/components/pagination-controls";
import { LocalTime } from "@/components/local-time";
import { label } from "@/lib/labels";

export const metadata: Metadata = {
  title: "Assignments",
};

const PAGE_SIZE = 25;

export default async function AssignmentsPage({
  searchParams,
}: {
  searchParams: Promise<{ offset?: string }>;
}) {
  const params = await searchParams;
  const offset = Number(params.offset ?? 0) || 0;
  const page = await listAllAssignments({ limit: PAGE_SIZE, offset });

  return (
    <>
      <section className="page-heading" aria-labelledby="assignments-title">
        <h1 id="assignments-title">Assignments</h1>
        <p>
          Which servers each user may connect to. Assign or remove them on the
          user page.
        </p>
      </section>

      {page.items.length === 0 ? (
        <EmptyState title="Server assignments" status="not-connected">
          <p>
            No users have been assigned to a VPN server yet. Assign one from a
            user&rsquo;s detail page.
          </p>
        </EmptyState>
      ) : (
        <section className="status-card" aria-labelledby="assigned-title">
          <h2 id="assigned-title">
            Server assignments
            <span className="count-badge">{page.total}</span>
          </h2>
          <DataTable
            caption="Assignments"
            headers={["User", "Server", "State", "Assigned", "Expires"]}
            emptyMessage="No server assignments exist."
            rows={page.items.map((item) => ({
              key: item.id,
              cells: [
                <Link key={item.id} href={`/users/${item.userId}`}>
                  {item.userEmail}
                </Link>,
                item.serverDisplayName,
                <span key="state" className={`badge badge--${item.state}`}>
                  {label(item.state)}
                </span>,
                <span key="assigned" className="muted">
                  <LocalTime value={item.assignedAt} dateOnly />
                </span>,
                item.expiresAt ? (
                  <span key="expires" className="muted">
                    <LocalTime value={item.expiresAt} dateOnly />
                  </span>
                ) : (
                  "—"
                ),
              ],
            }))}
          />
          <PaginationControls
            total={page.total}
            limit={page.limit}
            offset={page.offset}
            basePath="/assignments"
            searchParams={{}}
          />
        </section>
      )}
    </>
  );
}
