"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";
import { addRelay, removeRelay } from "@/lib/relays-actions";
import { MutationButton } from "./mutation-button";

export interface RelayServerOption {
  id: string;
  code: string;
  displayName: string;
}

export interface RelayProfileOption {
  code: string;
  displayName: string;
  /** Where it listens on its server; the relay forwards the same port. */
  port: number | null;
}

/**
 * A new relay: which server it leaves from (exit), which forwards to it
 * (via), the address people dial, and the port on the relay for each of the
 * exit's protocols to offer. Only the protocols given a port are offered.
 */
export function AddRelayForm({
  servers,
  profiles,
}: {
  servers: RelayServerOption[];
  profiles: RelayProfileOption[];
}) {
  const router = useRouter();
  const [name, setName] = useState("");
  const [exitId, setExitId] = useState(servers[0]?.id ?? "");
  const [viaId, setViaId] = useState(servers[1]?.id ?? "");
  const [host, setHost] = useState("");
  const startPorts = (): Record<string, string> =>
    Object.fromEntries(
      profiles.map((profile) => [
        profile.code,
        profile.port ? String(profile.port) : "",
      ]),
    );
  const [ports, setPorts] = useState<Record<string, string>>(startPorts);

  const chosen: Record<string, number> = {};
  for (const [code, value] of Object.entries(ports)) {
    const port = Number(value);
    if (value.trim() && Number.isInteger(port) && port >= 1 && port <= 65535) {
      chosen[code] = port;
    }
  }
  const ready =
    name.trim() !== "" &&
    host.trim() !== "" &&
    exitId !== "" &&
    viaId !== "" &&
    exitId !== viaId &&
    Object.keys(chosen).length > 0;

  return (
    <div className="auth-form">
      <div className="field">
        <label htmlFor="relay-name" className="field__label">
          Name in the app
        </label>
        <input
          id="relay-name"
          value={name}
          maxLength={96}
          placeholder="e.g. Germany via Tehran"
          onChange={(event) => setName(event.target.value)}
        />
      </div>
      <div className="field">
        <label htmlFor="relay-exit" className="field__label">
          Traffic leaves from (exit)
        </label>
        <select
          id="relay-exit"
          value={exitId}
          onChange={(event) => setExitId(event.target.value)}
        >
          {servers.map((server) => (
            <option key={server.id} value={server.id}>
              {server.displayName} ({server.code})
            </option>
          ))}
        </select>
      </div>
      <div className="field">
        <label htmlFor="relay-via" className="field__label">
          Forwarded by (the relay, e.g. the server in Iran)
        </label>
        <select
          id="relay-via"
          value={viaId}
          onChange={(event) => setViaId(event.target.value)}
        >
          {servers.map((server) => (
            <option key={server.id} value={server.id}>
              {server.displayName} ({server.code})
            </option>
          ))}
        </select>
      </div>
      <div className="field">
        <label htmlFor="relay-host" className="field__label">
          Relay&apos;s address people connect to
        </label>
        <input
          id="relay-host"
          value={host}
          maxLength={253}
          placeholder="e.g. 94.183.192.216"
          onChange={(event) => setHost(event.target.value)}
        />
      </div>
      <fieldset className="field">
        <legend className="field__label">
          Port on the relay for each protocol to offer (empty: not offered)
        </legend>
        {profiles.map((profile) => (
          <label key={profile.code} className="relay-port">
            <span>{profile.displayName}</span>
            <input
              inputMode="numeric"
              aria-label={`Port for ${profile.displayName}`}
              value={ports[profile.code] ?? ""}
              onChange={(event) =>
                setPorts({ ...ports, [profile.code]: event.target.value })
              }
            />
          </label>
        ))}
      </fieldset>
      {exitId !== "" && exitId === viaId ? (
        <p role="alert">The exit and the relay must be different servers.</p>
      ) : null}
      {ready ? (
        <MutationButton
          triggerLabel="Add relay"
          triggerClassName="button button--primary"
          confirmTitle={`Add ${name.trim()}`}
          confirmLabel="Add"
          confirmBody={
            <p>
              The relay&apos;s server is set up by itself through its agent, and
              the relay appears in the app for everyone who may use the exit as
              soon as that server reports in, usually within a minute.
            </p>
          }
          action={() =>
            addRelay({
              displayName: name.trim(),
              exitServerId: exitId,
              viaServerId: viaId,
              host: host.trim(),
              ports: chosen,
            })
          }
          onSuccess={() => {
            setName("");
            setHost("");
            setPorts(startPorts());
            router.refresh();
          }}
        />
      ) : (
        <button type="button" className="button button--primary" disabled>
          Add relay
        </button>
      )}
    </div>
  );
}

/** Takes a relay added in this panel off the app's server list. */
export function RemoveRelayButton({
  code,
  displayName,
}: {
  code: string;
  displayName: string;
}) {
  const router = useRouter();
  return (
    <MutationButton
      triggerLabel="Remove"
      triggerClassName="button button--danger"
      confirmTitle={`Remove ${displayName}`}
      confirmLabel="Remove"
      confirmDanger
      confirmBody={
        <p>
          It leaves the app&apos;s server list. Its server keeps forwarding
          until relay.env is deleted there and install.sh is run again.
        </p>
      }
      action={() => removeRelay(code)}
      onSuccess={() => router.refresh()}
    />
  );
}
