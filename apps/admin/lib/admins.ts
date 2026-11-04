import "server-only";
import { apiFetch } from "@/lib/api/client";
import { ApiError } from "@/lib/api/http-error";
import {
  type AdminItem,
  type AdminItemBody,
  toAdminItem,
} from "./admins-shape";

/** Every admin, or null when the viewer is not an owner. */
export async function listAdmins(): Promise<AdminItem[] | null> {
  try {
    const body = await apiFetch<{ items: AdminItemBody[] }>(
      "/v1/admin/admins/",
    );
    return body.items.map(toAdminItem);
  } catch (error) {
    if (error instanceof ApiError && error.status === 403) return null;
    throw error;
  }
}
