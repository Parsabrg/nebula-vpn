"use client";

import { useState, useTransition } from "react";
import {
  approveAccountRequest,
  rejectAccountRequest,
} from "@/lib/account-requests-actions";
import type { AccountRequestListItem } from "@/lib/account-requests";
import { ConfirmDialog } from "./confirm-dialog";
import { endedSession } from "@/lib/end-session";
import { LocalTime } from "@/components/local-time";
import { label } from "@/lib/labels";

export function RequestRow({ request }: { request: AccountRequestListItem }) {
  const [approveOpen, setApproveOpen] = useState(false);
  const [rejectOpen, setRejectOpen] = useState(false);
  const [reason, setReason] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [decision, setDecision] = useState<"approved" | "rejected" | null>(
    null,
  );
  const [pending, startTransition] = useTransition();

  function openApprove() {
    setError(null);
    setApproveOpen(true);
  }

  function openReject() {
    setError(null);
    setRejectOpen(true);
  }

  function handleApprove() {
    startTransition(async () => {
      const result = await approveAccountRequest(request.id);
      if (result.ok) {
        setApproveOpen(false);
        setDecision("approved");
      } else if (!endedSession(result)) {
        setError(result.message);
      }
    });
  }

  function handleReject() {
    startTransition(async () => {
      const result = await rejectAccountRequest(
        request.id,
        reason.trim() || null,
      );
      if (result.ok) {
        setRejectOpen(false);
        setDecision("rejected");
      } else if (!endedSession(result)) {
        setError(result.message);
      }
    });
  }

  const requestedAt = <LocalTime value={request.createdAt} />;

  if (decision) {
    return (
      <tr>
        <td data-label="Email">{request.email}</td>
        <td data-label="Username">{request.username ?? "—"}</td>
        <td data-label="Requested">{requestedAt}</td>
        <td data-label="Actions">
          <span className={`badge badge--${decision}`}>{label(decision)}</span>{" "}
          <small>
            {decision === "approved"
              ? `Activation email sent to ${request.email}`
              : "A not-approved email was sent"}
          </small>
        </td>
      </tr>
    );
  }

  return (
    <tr>
      <td data-label="Email">{request.email}</td>
      <td data-label="Username">{request.username ?? "—"}</td>
      <td data-label="Requested">{requestedAt}</td>
      <td data-label="Actions" className="data-table__actions">
        <button
          type="button"
          className="button button--primary"
          onClick={openApprove}
        >
          Approve
        </button>
        <button
          type="button"
          className="button button--danger"
          onClick={openReject}
        >
          Reject
        </button>
        <ConfirmDialog
          open={approveOpen}
          onOpenChange={setApproveOpen}
          title={`Approve ${request.email}`}
          confirmLabel="Approve"
          pending={pending}
          error={error}
          onConfirm={handleApprove}
        >
          <p>This sends an activation email to {request.email}.</p>
        </ConfirmDialog>
        <ConfirmDialog
          open={rejectOpen}
          onOpenChange={setRejectOpen}
          title={`Reject ${request.email}`}
          confirmLabel="Reject"
          danger
          pending={pending}
          error={error}
          onConfirm={handleReject}
        >
          <div className="field">
            <label
              htmlFor={`reject-reason-${request.id}`}
              className="field__label"
            >
              Note for admins (optional)
            </label>
            <textarea
              id={`reject-reason-${request.id}`}
              value={reason}
              onChange={(event) => {
                setReason(event.target.value);
              }}
            />
          </div>
          <p>
            {request.email} gets a short &ldquo;not approved&rdquo; email; the
            note is kept with the request and is not sent.
          </p>
        </ConfirmDialog>
      </td>
    </tr>
  );
}
