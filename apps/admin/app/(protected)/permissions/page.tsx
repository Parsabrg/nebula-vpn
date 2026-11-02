import type { Metadata } from "next";
import Link from "next/link";
import { listAllPermissions } from "@/lib/access";
import { DataTable } from "@/components/data-table";
import { EmptyState } from "@/components/empty-state";
import { PaginationControls } from "@/components/pagination-controls";
import { LocalTime } from "@/components/local-time";
import { label } from "@/lib/labels";

export const metadata: Metadata = {
  title: "Permissions",
};

const PAGE_SIZE = 25;

export default async function PermissionsPage({
  searchParams,
}: {
  searchParams: Promise<{ offset?: string }>;
}) {
  const params = await searchParams;
  const offset = Number(params.offset ?? 0) || 0;
  const page = await listAllPermissions({ limit: PAGE_SIZE, offset });

  return (
    <>
      <section className="page-heading" aria-labelledby="permissions-title">
        <h1 id="permissions-title">Permissions</h1>
        <p>
          Which protocols each user may use. Grant or revoke them on the user
          page.
        </p>
      </section>

      {page.items.length === 0 ? (
        <EmptyState title="Permission grants" status="not-connected">
          <p>
            No protocol permissions have been granted yet. Grant one from a
            user&rsquo;s detail page.
          </p>
        </EmptyState>
      ) : (
        <>
          <DataTable
            caption="Permissions"
            headers={["User", "Profile", "State", "Granted", "Expires"]}
            emptyMessage="No protocol permissions are granted."
            rows={page.items.map((item) => ({
              key: item.id,
              cells: [
                <Link key={item.id} href={`/users/${item.userId}`}>
                  {item.userEmail}
                </Link>,
                item.profileDisplayName,
                label(item.state),
                <LocalTime key="time-1" value={item.grantedAt} />,
                item.expiresAt ? (
                  <LocalTime key="time-2" value={item.expiresAt} />
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
            basePath="/permissions"
            searchParams={{}}
          />
        </>
      )}
    </>
  );
}
