import type { Metadata } from "next";
import { listPendingAccountRequests } from "@/lib/account-requests";
import { RequestRow } from "@/components/request-row";
import { DecisionNotes } from "@/components/decision-notes";

export const metadata: Metadata = {
  title: "Requests",
};

export default async function RequestsPage() {
  const requests = await listPendingAccountRequests();

  return (
    <>
      <section className="page-heading" aria-labelledby="requests-title">
        <h1 id="requests-title">Account requests</h1>
        <p>Review and decide pending account requests.</p>
      </section>

      <DecisionNotes>
        <section
          className="status-card"
          aria-labelledby="pending-requests-title"
        >
          <h2 id="pending-requests-title">
            Pending account requests
            {requests.length > 0 ? (
              <span className="count-badge">{requests.length}</span>
            ) : null}
          </h2>
          {requests.length === 0 ? (
            <p role="status">No pending account requests.</p>
          ) : (
            <table className="data-table" aria-label="Pending account requests">
              <thead>
                <tr>
                  <th scope="col">Email</th>
                  <th scope="col">Username</th>
                  <th scope="col">Requested</th>
                  <th scope="col">Actions</th>
                </tr>
              </thead>
              <tbody>
                {requests.map((request) => (
                  <RequestRow key={request.id} request={request} />
                ))}
              </tbody>
            </table>
          )}
        </section>
      </DecisionNotes>
    </>
  );
}
