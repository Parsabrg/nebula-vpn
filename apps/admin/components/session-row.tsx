"use client";

import { useState } from "react";
import { revokeUserSession } from "@/lib/users-actions";
import type { UserSessionListItem } from "@/lib/users";
import { MutationButton } from "./mutation-button";
import { LocalTime } from "@/components/local-time";

export function SessionRow({
  userId,
  session,
}: {
  userId: string;
  session: UserSessionListItem;
}) {
  const [current, setCurrent] = useState(session);

  return (
    <tr>
      <td data-label="Device">{current.deviceId}</td>
      <td data-label="State">
        <span className={`badge badge--${current.state}`}>{current.state}</span>
      </td>
      <td data-label="Expires">{<LocalTime value={current.expiresAt} />}</td>
      <td data-label="Last seen">
        {current.lastSeenAt ? <LocalTime value={current.lastSeenAt} /> : "—"}
      </td>
      <td data-label="Actions">
        {current.state === "active" ? (
          <MutationButton
            triggerLabel="Revoke"
            triggerClassName="button button--danger"
            confirmTitle="Revoke this session"
            confirmLabel="Revoke"
            confirmBody={
              <p>The device using this session is signed out immediately.</p>
            }
            action={() => revokeUserSession(userId, current.id)}
            onSuccess={setCurrent}
          />
        ) : (
          "—"
        )}
      </td>
    </tr>
  );
}
