"use client";

import { useId, useState } from "react";
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
  className = "button",
}: {
  label: string;
  className?: string;
  /** "Amsterdam 1", "VLESS (XHTTP+TLS)". */
  what: string;
  action: () => Promise<ActionResult<{ changed: number }>>;
}) {
  const [result, setResult] = useState<string | null>(null);
  return (
    <>
      <MutationButton
        triggerLabel={label}
        triggerClassName={className}
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
      {result ? (
        <span role="status" className="everyone__result">
          {result}
        </span>
      ) : null}
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

/** Pick a protocol, then give it to every user: one control, not a button
 * per protocol. */
export function ProfilesForEveryone({
  profiles,
}: {
  profiles: { id: string; name: string }[];
}) {
  const selectId = useId();
  const [selected, setSelected] = useState(profiles[0]?.id ?? "");
  const profile = profiles.find((item) => item.id === selected);
  if (!profile) return null;
  return (
    <div className="everyone">
      <div className="field everyone__field">
        <label htmlFor={selectId} className="field__label">
          Protocol
        </label>
        <select
          id={selectId}
          value={selected}
          onChange={(event) => setSelected(event.target.value)}
        >
          {profiles.map((item) => (
            <option key={item.id} value={item.id}>
              {item.name}
            </option>
          ))}
        </select>
      </div>
      <EveryoneAccessButton
        key={profile.id}
        label="Give to every user"
        what={profile.name}
        className="button button--primary"
        action={() => grantProfileToEveryone(profile.id)}
      />
    </div>
  );
}
