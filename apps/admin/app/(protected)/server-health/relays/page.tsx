import type { Metadata } from "next";
import { AddRelayForm, RemoveRelayButton } from "@/components/relay-controls";
import { EmptyState } from "@/components/empty-state";
import { relaySetup } from "@/lib/relay-setup";
import { listRelays } from "@/lib/relays";
import { listProtocolProfiles, listVpnServers } from "@/lib/topology";

export const metadata: Metadata = {
  title: "Relays",
};

export default async function RelaysPage() {
  const [{ relays, reportUrl }, servers, profiles] = await Promise.all([
    listRelays(),
    listVpnServers(),
    listProtocolProfiles(),
  ]);
  // One port per protocol: an ad-block sibling shares its base's.
  const offerable = profiles.filter(
    (profile) =>
      !profile.code.endsWith("-adblock") && profile.code !== "wireguard",
  );

  return (
    <>
      <section className="page-heading" aria-labelledby="relays-title">
        <h1 id="relays-title">Relays</h1>
        <p>
          A relay is a server that forwards to another one, for networks that
          reach the relay but not the other server: for example a server in Iran
          forwarding to one abroad. The app lists it as a server of its own,
          such as &ldquo;Germany via Tehran&rdquo;.
        </p>
      </section>

      {relays.length === 0 ? (
        <EmptyState title="No relays yet" status="not-connected">
          <p>Add one below.</p>
        </EmptyState>
      ) : (
        relays.map((relay) => (
          <section key={relay.code} className="status-card">
            <h2>
              {relay.displayName}{" "}
              <span className="badge">
                {relay.up ? "Up" : "Under maintenance"}
              </span>
            </h2>
            <p>
              {relay.viaName} ({relay.host}) forwards to {relay.exitName}.{" "}
              {relay.source === "settings"
                ? "Set in the server's NEBULA_RELAYS."
                : "Added in this panel."}
            </p>
            <p>
              Ports:{" "}
              {relay.ports
                .map((port) => `${port.profileCode} ${port.port}`)
                .join(", ")}
            </p>
            {relay.up ? null : (
              <p className="section-note">
                Under maintenance until {relay.viaName} reports in, usually a
                minute after it is added: {relay.viaName}&apos;s agent sets it
                up. If it stays so, {relay.viaName} may need its{" "}
                <code>install.sh</code> run once more, or the commands below.
              </p>
            )}
            <details>
              <summary>Set up {relay.viaName} by hand</summary>
              <p className="section-note">
                On {relay.viaName}, in the Nebula folder (it must have joined
                this panel first, from Add server):
              </p>
              <pre className="command">{relaySetup(relay, reportUrl)}</pre>
            </details>
            {relay.source === "panel" ? (
              <RemoveRelayButton
                code={relay.code}
                displayName={relay.displayName}
              />
            ) : null}
          </section>
        ))
      )}

      <section className="status-card" aria-labelledby="add-relay-title">
        <h2 id="add-relay-title">Add relay</h2>
        {servers.length < 2 ? (
          <p>A relay needs two servers: add the second one first.</p>
        ) : (
          <AddRelayForm
            servers={servers.map((server) => ({
              id: server.id,
              code: server.code,
              displayName: server.displayName,
            }))}
            profiles={offerable.map((profile) => ({
              code: profile.code,
              displayName: profile.displayName,
              port: profile.requiredPort,
            }))}
          />
        )}
      </section>
    </>
  );
}
