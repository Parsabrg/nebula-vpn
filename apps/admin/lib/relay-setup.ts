/** A relay as the panel lists it. */
export interface RelayItem {
  code: string;
  displayName: string;
  exitCode: string;
  exitName: string;
  exitHost: string;
  viaCode: string;
  viaName: string;
  /** The relay's address the app dials. */
  host: string;
  ports: {
    profileCode: string;
    /** On the relay. */
    port: number;
    /** Where the profile listens on the exit; null when not known. */
    exitPort: number | null;
    udp: boolean;
  }[];
  /** "settings": NEBULA_RELAYS on the server; "panel": added here. */
  source: "settings" | "panel";
  up: boolean;
}

const IPV4 = /^\d{1,3}(\.\d{1,3}){3}$/;

/**
 * What to run on the relay's server: relay.env, which install.sh reads to
 * forward the ports and to start the 30-second report, then the installer.
 * The token is the one in the control plane's compose.env, never shown here.
 */
export function relaySetup(relay: RelayItem, reportUrl: string): string {
  const forwards = relay.ports
    .filter((port) => port.exitPort !== null)
    .map((port) => `${port.port}/${port.udp ? "udp" : "tcp"}:${port.exitPort}`);
  const target = IPV4.test(relay.exitHost)
    ? relay.exitHost
    : `<IPv4 address of ${relay.exitName}>`;
  return [
    "sudo tee /etc/nebula/relay.env <<'EOF'",
    `NEBULA_RELAY_TARGET=${target}`,
    `NEBULA_RELAY_PORTS=${forwards.join(" ")}`,
    `NEBULA_RELAY_REPORT_URL=${reportUrl.replace(/\/+$/, "")}/v1/relays/${relay.code}/up`,
    "NEBULA_RELAY_REPORT_TOKEN=<NEBULA_RELAY_REPORT_TOKEN from the control plane's /etc/nebula/compose.env>",
    "EOF",
    "sudo ./install.sh",
  ].join("\n");
}
