import { describe, expect, it } from "vitest";
import { type RelayItem, relaySetup } from "@/lib/relay-setup";

const relay: RelayItem = {
  code: "study-lab-1-via-tehran",
  displayName: "Germany via Tehran",
  exitCode: "study-lab-1",
  exitName: "Germany",
  exitHost: "91.107.170.215",
  viaCode: "tehran",
  viaName: "Tehran",
  host: "94.183.192.216",
  ports: [
    { profileCode: "vless-tcp-tls", port: 2053, exitPort: 8449, udp: false },
    { profileCode: "hysteria2", port: 443, exitPort: 8450, udp: true },
    { profileCode: "unknown", port: 9999, exitPort: null, udp: false },
  ],
  source: "panel",
  up: true,
};

describe("relaySetup", () => {
  it("forwards each known port and reports to the control plane", () => {
    const text = relaySetup(relay, "https://cdn.example.org/");
    expect(text).toContain("NEBULA_RELAY_TARGET=91.107.170.215");
    expect(text).toContain("NEBULA_RELAY_PORTS=2053/tcp:8449 443/udp:8450");
    expect(text).toContain(
      "NEBULA_RELAY_REPORT_URL=https://cdn.example.org/v1/relays/study-lab-1-via-tehran/up",
    );
    expect(text).toContain("sudo ./install.sh");
  });

  it("asks for the exit's address when it is a name", () => {
    const text = relaySetup(
      { ...relay, exitHost: "de.example.org" },
      "https://x",
    );
    expect(text).toContain("NEBULA_RELAY_TARGET=<IPv4 address of Germany>");
  });
});
