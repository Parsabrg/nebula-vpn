"use server";

import { type ActionResult, toActionResult } from "@/lib/api/action-result";
import { apiFetch } from "@/lib/api/client";

export interface NewRelay {
  displayName: string;
  exitServerId: string;
  viaServerId: string;
  host: string;
  ports: Record<string, number>;
}

/** Add a relay to the app's server list. */
export async function addRelay(relay: NewRelay): Promise<ActionResult<null>> {
  return toActionResult(
    apiFetch<null>("/v1/admin/relays", {
      method: "POST",
      body: {
        display_name: relay.displayName,
        exit_server_id: relay.exitServerId,
        via_server_id: relay.viaServerId,
        host: relay.host,
        ports: relay.ports,
      },
    }).then(() => null),
  );
}

/** Take a relay added here off the app's server list. */
export async function removeRelay(code: string): Promise<ActionResult<null>> {
  return toActionResult(
    apiFetch<null>(`/v1/admin/relays/${encodeURIComponent(code)}/delete`, {
      method: "POST",
      body: {},
    }).then(() => null),
  );
}
