import "server-only";
import { apiFetch } from "@/lib/api/client";

export interface Passkey {
  id: string;
  name: string;
  createdAt: string;
  lastUsedAt: string | null;
}

export async function listPasskeys(): Promise<Passkey[]> {
  const body = await apiFetch<{
    items: {
      id: string;
      name: string;
      created_at: string;
      last_used_at: string | null;
    }[];
  }>("/v1/admin/auth/passkeys");
  return body.items.map((item) => ({
    id: item.id,
    name: item.name,
    createdAt: item.created_at,
    lastUsedAt: item.last_used_at,
  }));
}
