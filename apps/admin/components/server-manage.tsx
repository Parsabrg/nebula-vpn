"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";
import { label } from "@/lib/labels";
import {
  renameServer,
  type ServerState,
  setDnsTunnel,
  setServerState,
} from "@/lib/topology-actions";
import { DnsTunnelStatusView } from "./dns-tunnel-status";
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
 * app, its state as three described choices, "Give every user this
 * server", and its DNS tunnel. Save applies them together; the step-up prompt
 * and the error, when there is one, come from MutationButton.
 */
export function ServerManage({
  serverId,
  code,
  name,
  state,
  dnsTunnel = [],
}: {
  serverId: string;
  code: string;
  name: string;
  state: string;
  /** Its DNS tunnel names; none when it has no tunnel. */
  dnsTunnel?: string[];
}) {
  const router = useRouter();
  const [draftName, setDraftName] = useState(name);
  const saved = dnsTunnel.join(", ");
  const [draftTunnel, setDraftTunnel] = useState(saved);
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
          <div className="field">
            <label htmlFor={`server-dns-${serverId}`} className="field__label">
              DNS tunnel
            </label>
            <input
              id={`server-dns-${serverId}`}
              value={draftTunnel}
              placeholder="t1.example.org"
              maxLength={600}
              onChange={(event) => setDraftTunnel(event.target.value)}
            />
            <p className="field__help">
              A last-resort route that still works when only DNS gets through
              (slow). Give it a name under your domain; a second name, comma
              separated, is a backup. Empty turns it off. Needs VLESS Encryption
              on this server.
            </p>
            {saved && draftTunnel === saved && (
              <DnsTunnelStatusView serverId={serverId} />
            )}
          </div>
          <ServerForEveryone serverId={serverId} name={name} />
        </div>
      }
      action={async () => {
        if (draftName.trim() !== name) {
          const renamed = await renameServer(serverId, draftName);
          if (!renamed.ok) return renamed;
        }
        if (draftTunnel.trim() !== saved) {
          const names = draftTunnel
            .split(",")
            .map((part) => part.trim())
            .filter(Boolean);
          const set = await setDnsTunnel(serverId, names);
          if (!set.ok) return set;
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
