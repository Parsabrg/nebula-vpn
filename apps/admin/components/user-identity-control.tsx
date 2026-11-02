"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";
import { changeIdentity } from "@/lib/users-actions";
import { MutationButton } from "./mutation-button";

/** Correct an account's email or username. Only changed fields are sent. */
export function UserIdentityControl({
  userId,
  email,
  username,
}: {
  userId: string;
  email: string;
  username: string | null;
}) {
  const router = useRouter();
  const [draftEmail, setDraftEmail] = useState(email);
  const [draftUsername, setDraftUsername] = useState(username ?? "");

  return (
    <MutationButton
      triggerLabel="Edit email or username"
      triggerClassName="button"
      confirmTitle="Edit email or username"
      confirmLabel="Save"
      confirmBody={
        <>
          <div className="field">
            <label htmlFor="identity-email" className="field__label">
              Email
            </label>
            <input
              id="identity-email"
              type="email"
              value={draftEmail}
              onChange={(event) => setDraftEmail(event.target.value)}
            />
          </div>
          <div className="field">
            <label htmlFor="identity-username" className="field__label">
              Username (leave empty for none)
            </label>
            <input
              id="identity-username"
              value={draftUsername}
              onChange={(event) => setDraftUsername(event.target.value)}
            />
          </div>
          <p>
            The person signs in with the new values from now on. Their devices,
            sessions and VPN access stay as they are.
          </p>
        </>
      }
      action={() =>
        changeIdentity(userId, {
          ...(draftEmail.trim() !== email ? { email: draftEmail } : {}),
          ...(draftUsername.trim() !== (username ?? "")
            ? { username: draftUsername }
            : {}),
        })
      }
      onSuccess={() => router.refresh()}
    />
  );
}
