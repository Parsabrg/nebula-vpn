"use client";

import { useState } from "react";
import type { ActionResult } from "@/lib/api/action-result";
import {
  assignServerToEveryone,
  grantProfileToEveryone,
} from "@/lib/access-actions";
import { MutationButton } from "./mutation-button";

/** Give every active or not-yet-activated account one server or protocol. */
function EveryoneAccessButton({
  label,
  what,
  action,
}: {
  label: string;
  /** "Amsterdam 1", "VLESS (XHTTP+TLS)". */
  what: string;
  action: () => Promise<ActionResult<{ changed: number }>>;
}) {
  const [result, setResult] = useState<string | null>(null);
  return (
    <>
      <MutationButton
        triggerLabel={label}
        triggerClassName="button"
        confirmTitle={`${what} for every user`}
        confirmLabel="Give access"
        confirmBody={
          <p>
            Every active account, and every account still to be activated, gets{" "}
            {what}. Disabled and deleted accounts are left out. Users who
            already have it are not changed.
          </p>
        }
        action={action}
        onSuccess={({ changed }) =>
          setResult(
            changed === 1
              ? "1 user gained access."
              : `${changed} users gained access.`,
          )
        }
      />
      {result ? <span role="status"> {result}</span> : null}
    </>
  );
}

export function ServerForEveryone({
  serverId,
  name,
}: {
  serverId: string;
  name: string;
}) {
  return (
    <EveryoneAccessButton
      label="Give every user this server"
      what={name}
      action={() => assignServerToEveryone(serverId)}
    />
  );
}

export function ProfileForEveryone({
  profileId,
  name,
}: {
  profileId: string;
  name: string;
}) {
  return (
    <EveryoneAccessButton
      label={`Give every user ${name}`}
      what={name}
      action={() => grantProfileToEveryone(profileId)}
    />
  );
}
