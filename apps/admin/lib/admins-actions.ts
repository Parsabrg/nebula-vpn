"use server";

import { type ActionResult, toActionResult } from "@/lib/api/action-result";
import { apiFetch } from "@/lib/api/client";
import {
  type AdminItem,
  type AdminItemBody,
  type AdminRole,
  type AdminSessionBody,
  type AdminSessionItem,
  toAdminItem,
  toAdminSession,
} from "./admins-shape";

const base = (adminId: string) =>
  `/v1/admin/admins/${encodeURIComponent(adminId)}`;

export async function inviteAdmin(fields: {
  email: string;
  username: string;
  role: AdminRole;
}): Promise<ActionResult<{ admin: AdminItem; temporaryPassword: string }>> {
  return toActionResult(
    apiFetch<{ admin: AdminItemBody; temporary_password: string }>(
      "/v1/admin/admins/",
      {
        method: "POST",
        body: {
          email: fields.email.trim(),
          role: fields.role,
          ...(fields.username.trim()
            ? { username: fields.username.trim() }
            : {}),
        },
      },
    ).then((body) => ({
      admin: toAdminItem(body.admin),
      temporaryPassword: body.temporary_password,
    })),
  );
}

export async function changeAdminRole(
  adminId: string,
  role: AdminRole,
): Promise<ActionResult<AdminItem>> {
  return toActionResult(
    apiFetch<AdminItemBody>(`${base(adminId)}/role`, {
      method: "POST",
      body: { role },
    }).then(toAdminItem),
  );
}

export async function setAdminDisabled(
  adminId: string,
  disabled: boolean,
): Promise<ActionResult<AdminItem>> {
  return toActionResult(
    apiFetch<AdminItemBody>(
      `${base(adminId)}/${disabled ? "disable" : "reactivate"}`,
      { method: "POST" },
    ).then(toAdminItem),
  );
}

export async function loadAdminSessions(
  adminId: string,
): Promise<ActionResult<AdminSessionItem[]>> {
  return toActionResult(
    apiFetch<{ items: AdminSessionBody[] }>(`${base(adminId)}/sessions`).then(
      (body) => body.items.map(toAdminSession),
    ),
  );
}

export async function endAdminSession(
  adminId: string,
  sessionId: string,
): Promise<ActionResult<null>> {
  return toActionResult(
    apiFetch<unknown>(
      `${base(adminId)}/sessions/${encodeURIComponent(sessionId)}/end`,
      { method: "POST" },
    ).then(() => null),
  );
}

export async function endAllAdminSessions(
  adminId: string,
): Promise<ActionResult<null>> {
  return toActionResult(
    apiFetch<unknown>(`${base(adminId)}/sessions/end-all`, {
      method: "POST",
    }).then(() => null),
  );
}
