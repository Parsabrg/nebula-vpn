import { AdminShell } from "@/components/admin-shell";
import { listPendingAccountRequests } from "@/lib/account-requests";
import { requireAdminSession } from "@/lib/auth/require-session";

export default async function ProtectedLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  const session = await requireAdminSession();
  // The count beside Requests in the sidebar. Not every role may list
  // requests, and the sidebar must not fail with it: no count then.
  const pendingRequests = await listPendingAccountRequests().then(
    (requests) => requests.length,
    () => 0,
  );

  return (
    <AdminShell role={session.role} pendingRequests={pendingRequests}>
      {children}
    </AdminShell>
  );
}
