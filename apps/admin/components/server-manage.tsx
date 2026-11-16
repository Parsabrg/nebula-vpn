"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";
import { label } from "@/lib/labels";
import {
  renameServer,
  type ServerState,
  setServerState,
} from "@/lib/topology-actions";
import { ServerForEveryone } from "./everyone-access-button";
import { MutationButton } from "./mutation-button";

/** What each state does, said where the choice is made. */
const STATE_MEANING: Record<ServerState, string> = {
  active: "Offered to the app and takes new connections.",
  maintenance:
    "Takes no new connections and leaves the app's server list. Tunnels already on it keep running, and their traffic and revocations are still handled.",
  disabled:
    "Out of service: not offered, and its traffic and revocations are no longer handled. For a server being retired or rebuilt.",
};

const STATES: readonly ServerState[] = ["active", "maintenance", "disabled"];

/**
 * A server's Manage dialog, as the design has it: the name shown in the
 * app, its state as three described choices, and "Give every user this
 * server". Save renames and changes the state together; the step-up prompt
 * and the error, when there is one, come from MutationButton.
 */
export function ServerManage({
  serverId,
  code,
  name,
  state,
}: {
  serverId: string;
  code: string;
  name: string;
  state: string;
}) {
  const router = useRouter();
  const [draftName, setDraftName] = useState(name);
  const [draftState, setDraftState] = useState<ServerState>(
    STATES.includes(state as ServerState) ? (state as ServerState) : "active",
  );

  return (
    <MutationButton
      triggerLabel="Manage"
      triggerClassName="button button--small"
      confirmTitle={name}
      confirmLabel="Save"
      confirmBody={
        <div className="server-manage">
          <div className="field">
            <label htmlFor={`server-name-${serverId}`} className="field__label">
              Name shown in the app
            </label>
            <input
              id={`server-name-${serverId}`}
              value={draftName}
              maxLength={96}
              onChange={(event) => setDraftName(event.target.value)}
            />
            <p className="field__help">
              The server code ({code}) stays the same.
            </p>
          </div>
          <fieldset className="choice-list">
            <legend className="visually-hidden">State</legend>
            {STATES.map((option) => (
              <label
                key={option}
                className={`choice${draftState === option ? " is-selected" : ""}`}
              >
                <input
                  type="radio"
                  name={`server-state-${serverId}`}
                  value={option}
                  checked={draftState === option}
                  onChange={() => setDraftState(option)}
                />
                <span>
                  <strong>{label(option)}</strong>
                  <span>{STATE_MEANING[option]}</span>
                </span>
              </label>
            ))}
          </fieldset>
          <ServerForEveryone serverId={serverId} name={name} />
        </div>
      }
      action={async () => {
        if (draftName.trim() !== name) {
          const renamed = await renameServer(serverId, draftName);
          if (!renamed.ok) return renamed;
        }
        if (draftState !== state) {
          const changed = await setServerState(serverId, draftState);
          if (!changed.ok) return changed;
        }
        return { ok: true as const, data: null };
      }}
      onSuccess={() => router.refresh()}
    />
  );
}
