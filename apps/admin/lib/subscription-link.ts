import "server-only";
import { apiFetch } from "@/lib/api/client";

export interface LinkOption {
  value: string;
  label: string;
}

/** The address subscription links name, and the ones on offer. */
export async function getSubscriptionLink(): Promise<{
  choice: string;
  options: LinkOption[];
}> {
  return apiFetch<{ choice: string; options: LinkOption[] }>(
    "/v1/admin/subscription-link",
  );
}
