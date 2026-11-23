"use client";

import { type FormEvent, useState } from "react";
import { type JoinToken, mintJoinToken } from "@/lib/node-actions";
import { endedSession } from "@/lib/end-session";
import { LocalTime } from "@/components/local-time";

/**
 * Adding a server: name it, then paste one command on it. Before this it
 * took a CLI command on this server and a hand install on the new one.
 * A name already taken offers to rebuild that server instead: the same
 * command on a reinstalled machine, keeping its users, relays and name.
 */
export function AddServerForm() {
  const [joined, setJoined] = useState<JoinToken | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [pending, setPending] = useState(false);
  const [copied, setCopied] = useState(false);
  // The name of an existing server the admin may rebuild.
  const [taken, setTaken] = useState<string | null>(null);
  const [rebuilt, setRebuilt] = useState(false);

  async function mint(label: string, rebuild: boolean) {
    setPending(true);
    setError(null);
    const result = await mintJoinToken(label, rebuild);
    setPending(false);
    if (!result.ok) {
      if (endedSession(result)) {
        return;
      }
      if (result.code === "conflict" && !rebuild) {
        setTaken(label);
        return;
      }
      setError(result.message);
      return;
    }
    setRebuilt(rebuild);
    setJoined(result.data);
  }

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setTaken(null);
    const label = String(new FormData(event.currentTarget).get("label") ?? "")
      .trim()
      .toLowerCase()
      // "Amsterdam 1" means amsterdam-1; the browser refusing it did not help.
      .replace(/[^a-z0-9-]+/g, "-")
      .replace(/^-+|-+$/g, "");
    await mint(label, false);
  }

  if (joined) {
    const command = `sudo ./install.sh --join ${joined.apiUrl} --token ${joined.token}`;
    return (
      <div>
        <p role="status">
          On the new server (Ubuntu or Debian), clone Nebula, then run this in
          its folder. It works once, until{" "}
          {<LocalTime value={joined.expiresAt} />}.
        </p>
        <pre className="command" aria-label="Command for the new server">
          {command}
        </pre>
        <button
          type="button"
          className="button button--primary"
          onClick={async () => {
            await navigator.clipboard.writeText(command);
            setCopied(true);
          }}
        >
          {copied ? "Copied" : "Copy command"}
        </button>
        {rebuilt ? (
          <p className="section-note">
            Run it on the reinstalled machine. It joins as{" "}
            <strong>{joined.label}</strong> again: its users, relays, name and
            protocols stay, and their connections are set up on it again by
            themselves within a few minutes.
          </p>
        ) : (
          <p className="section-note">
            It asks for the new server&apos;s domain name, installs the VPN
            engines and joins as <strong>{joined.label}</strong>, with its
            protocols enabled. Then assign it to users from their pages.
          </p>
        )}
      </div>
    );
  }

  return (
    <form className="auth-form" onSubmit={submit}>
      <div className="field">
        <label htmlFor="label" className="field__label">
          Name for the new server
        </label>
        <input
          id="label"
          name="label"
          required
          maxLength={64}
          placeholder="e.g. amsterdam-1"
        />
        <p className="section-note">
          Becomes lowercase letters, digits and dashes.
        </p>
      </div>
      {error ? <p role="alert">{error}</p> : null}
      {taken ? (
        <div role="alert">
          <p>
            A server is already called <strong>{taken}</strong>. Reinstalled
            that machine, or moved it to a new one? Rebuild it: it keeps its
            users, relays and name.
          </p>
          <button
            type="button"
            className="button"
            disabled={pending}
            onClick={() => mint(taken, true)}
          >
            Rebuild {taken}
          </button>
        </div>
      ) : null}
      <button
        type="submit"
        className="button button--primary"
        disabled={pending}
      >
        {pending ? "Creating…" : "Create join command"}
      </button>
    </form>
  );
}
