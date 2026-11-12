import "server-only";
import { apiFetch } from "@/lib/api/client";
import type { RelayItem } from "@/lib/relay-setup";

interface RelayListBody {
  items: {
    code: string;
    display_name: string;
    exit_code: string;
    exit_name: string;
    exit_host: string;
    via_code: string;
    via_name: string;
    host: string;
    ports: {
      profile_code: string;
      port: number;
      exit_port: number | null;
      udp: boolean;
    }[];
    source: "settings" | "panel";
    up: boolean;
  }[];
  report_url: string;
}

/** Every relay, from the server's settings and from this panel. */
export async function listRelays(): Promise<{
  relays: RelayItem[];
  reportUrl: string;
}> {
  const body = await apiFetch<RelayListBody>("/v1/admin/relays");
  return {
    reportUrl: body.report_url,
    relays: body.items.map((item) => ({
      code: item.code,
      displayName: item.display_name,
      exitCode: item.exit_code,
      exitName: item.exit_name,
      exitHost: item.exit_host,
      viaCode: item.via_code,
      viaName: item.via_name,
      host: item.host,
      ports: item.ports.map((port) => ({
        profileCode: port.profile_code,
        port: port.port,
        exitPort: port.exit_port,
        udp: port.udp,
      })),
      source: item.source,
      up: item.up,
    })),
  };
}
