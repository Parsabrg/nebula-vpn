"use server";

import { type ActionResult, toActionResult } from "@/lib/api/action-result";
import { apiFetch } from "@/lib/api/client";

export interface JoinToken {
  token: string;
  label: string;
  expiresAt: string;
  apiUrl: string;
}

/**
 * A one-time token for a new server to join this deployment; [rebuild], for
 * the existing server of that name, reinstalled.
 */
export async function mintJoinToken(
  label: string,
  rebuild = false,
): Promise<ActionResult<JoinToken>> {
  return toActionResult(
    apiFetch<{
      token: string;
      label: string;
      expires_at: string;
      api_url: string;
    }>("/v1/admin/nodes/enrollment-tokens", {
      method: "POST",
      body: { label, rebuild },
    }).then((body) => ({
      token: body.token,
      label: body.label,
      expiresAt: body.expires_at,
      apiUrl: body.api_url,
    })),
  );
}
