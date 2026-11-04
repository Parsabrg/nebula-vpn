import type { Metadata } from "next";
import { AdminsPanel } from "@/components/admins-panel";
import { listAdmins } from "@/lib/admins";

export const metadata: Metadata = {
  title: "Admins",
};

export default async function AdminsPage() {
  const admins = await listAdmins();

  return (
    <>
      <section className="page-heading" aria-labelledby="admins-title">
        <h1 id="admins-title">Admins</h1>
        <p>
          Who can sign in to this panel, and with what role. Every change needs
          a fresh code and is in the audit log.
        </p>
      </section>
      {admins === null ? (
        <p role="status">Only an owner can see and manage admins.</p>
      ) : (
        <AdminsPanel initial={admins} />
      )}
    </>
  );
}
