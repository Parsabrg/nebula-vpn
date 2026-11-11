"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";
import type { UserState } from "@/lib/users";
import { deleteUser, reissueActivation } from "@/lib/users-actions";
import { LocalTime } from "./local-time";
import { MutationButton } from "./mutation-button";

/** An account deleted already: kept under a placeholder address. */
function isDeletedAccount(email: string): boolean {
  return email.toLowerCase().endsWith("@deleted.invalid");
}

/** Send the activation link again, and delete the account. */
export function UserAccountActions({
  userId,
  email,
  state,
}: {
  userId: string;
  email: string;
  state: UserState;
}) {
  const router = useRouter();
  const [linkExpiresAt, setLinkExpiresAt] = useState<string | null>(null);

  // Deleted already: the row is kept, under a placeholder address, for its
  // audit entries and traffic totals. The API refuses a second deletion, and
  // offering one showed "Something went wrong".
  if (isDeletedAccount(email)) {
    return (
      <p className="section-note">
        Deleted account. Only its audit entries and traffic totals remain.
      </p>
    );
  }

  return (
    <div className="button-row">
      {state === "pending_activation" ? (
        <MutationButton
          triggerLabel="Send activation email again"
          triggerClassName="button"
          confirmTitle="Send the activation email again"
          confirmLabel="Send"
          confirmBody={
            <p>
              {email} gets a new link to set a password. Any earlier link stops
              working.
            </p>
          }
          action={() => reissueActivation(userId)}
          onSuccess={(sent) => setLinkExpiresAt(sent.expiresAt)}
        />
      ) : null}
      {linkExpiresAt ? (
        <p role="status">
          Sent. The link works until <LocalTime value={linkExpiresAt} />.
        </p>
      ) : null}
      <MutationButton
        triggerLabel="Delete user"
        triggerClassName="button button--danger"
        confirmTitle={`Delete ${email}`}
        confirmLabel="Delete"
        confirmBody={
          <>
            <p>
              This cannot be undone. The email, username, password, devices,
              sessions, account request and emails are erased, and every VPN
              connection of this account stops on every server.
            </p>
            <p>
              Only audit entries and traffic totals stay, under a random id.
              Backups keep the old data for up to 30 days.
            </p>
          </>
        }
        action={() => deleteUser(userId)}
        onSuccess={() => {
          router.push("/users");
          router.refresh();
        }}
      />
    </div>
  );
}
