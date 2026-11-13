"use server";

import { type ActionResult, toActionResult } from "@/lib/api/action-result";
import { apiFetch } from "@/lib/api/client";

/** Name [choice] in new subscription links ("auto" for Automatic). */
export async function setSubscriptionLink(
  choice: string,
): Promise<ActionResult<null>> {
  return toActionResult(
    apiFetch<null>("/v1/admin/subscription-link", {
      method: "POST",
      body: { choice },
    }).then(() => null),
  );
}
