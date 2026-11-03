import type { Metadata } from "next";
import Link from "next/link";
import { listAllPermissions } from "@/lib/access";
import { groupByUser } from "@/lib/group-grants";
import { listProtocolProfiles } from "@/lib/topology";
import { ProfilesForEveryone } from "@/components/everyone-access-button";
import { DataTable } from "@/components/data-table";
import { EmptyState } from "@/components/empty-state";
import { PaginationControls } from "@/components/pagination-controls";

export const metadata: Metadata = {
  title: "Permissions",
};

// Rows come sorted by user, so a page holds whole users unless one has more
// grants than fit; that user then continues on the next page.
const PAGE_SIZE = 200;

export default async function PermissionsPage({
  searchParams,
}: {
  searchParams: Promise<{ offset?: string }>;
}) {
  const params = await searchParams;
  const offset = Number(params.offset ?? 0) || 0;
  const [page, profiles] = await Promise.all([
    listAllPermissions({ limit: PAGE_SIZE, offset }),
    listProtocolProfiles(),
  ]);

  return (
    <>
      <section className="page-heading" aria-labelledby="permissions-title">
        <h1 id="permissions-title">Permissions</h1>
        <p>
          Which protocols each user may use. Grant or revoke them on the user
          page, or give one to every user below.
        </p>
      </section>

      <section className="status-card" aria-labelledby="everyone-title">
        <h2 id="everyone-title">For every user</h2>
        <p className="section-note">
          Every active account, and every account still to be activated, gets
          the protocol. Users who already have it are not changed.
        </p>
        <ProfilesForEveryone
          profiles={profiles
            .filter((profile) => profile.state !== "deprecated")
            .map((profile) => ({ id: profile.id, name: profile.displayName }))}
        />
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
            headers={["User", "Protocols", "Not in use"]}
            emptyMessage="No protocol permissions are granted."
            rows={groupByUser(page.items).map((group) => ({
              key: group.userId,
              cells: [
                <Link key={group.userId} href={`/users/${group.userId}`}>
                  {group.userEmail}
                </Link>,
                group.enabled.length > 0 ? (
                  <ul key="protocols" className="chips">
                    {group.enabled.map((name) => (
                      <li key={name}>{name}</li>
                    ))}
                  </ul>
                ) : (
                  "None"
                ),
                group.other,
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
