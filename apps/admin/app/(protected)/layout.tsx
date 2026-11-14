import { AdminShell } from "@/components/admin-shell";
import { requireAdminSession } from "@/lib/auth/require-session";

export default async function ProtectedLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  const session = await requireAdminSession();

  return <AdminShell role={session.role}>{children}</AdminShell>;
}
