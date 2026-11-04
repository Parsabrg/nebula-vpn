/** The admin list's shapes, shared by the page and its server actions. */

export type AdminRole = "owner" | "operator" | "auditor";
export type AdminState = "active" | "disabled";

export const ADMIN_ROLES: {
  value: AdminRole;
  label: string;
  detail: string;
}[] = [
  { value: "owner", label: "Owner", detail: "everything, including admins" },
  {
    value: "operator",
    label: "Operator",
    detail: "users, servers and access; not admins",
  },
  {
    value: "auditor",
    label: "Auditor",
    detail: "reads everything, changes nothing",
  },
];

export interface AdminItemBody {
  id: string;
  email: string;
  username: string | null;
  role: AdminRole;
  state: AdminState;
  has_authenticator: boolean;
  created_at: string;
  disabled_at: string | null;
  is_you: boolean;
}

export interface AdminItem {
  id: string;
  email: string;
  username: string | null;
  role: AdminRole;
  state: AdminState;
  hasAuthenticator: boolean;
  createdAt: string;
  disabledAt: string | null;
  isYou: boolean;
}

export interface AdminSessionBody {
  session_id: string;
  mfa_method: string;
  created_at: string;
  last_seen_at: string;
  expires_at: string;
  is_this_one: boolean;
}

export interface AdminSessionItem {
  sessionId: string;
  mfaMethod: string;
  createdAt: string;
  lastSeenAt: string;
  expiresAt: string;
  isThisOne: boolean;
}

export function toAdminItem(body: AdminItemBody): AdminItem {
  return {
    id: body.id,
    email: body.email,
    username: body.username,
    role: body.role,
    state: body.state,
    hasAuthenticator: body.has_authenticator,
    createdAt: body.created_at,
    disabledAt: body.disabled_at,
    isYou: body.is_you,
  };
}

export function toAdminSession(body: AdminSessionBody): AdminSessionItem {
  return {
    sessionId: body.session_id,
    mfaMethod: body.mfa_method,
    createdAt: body.created_at,
    lastSeenAt: body.last_seen_at,
    expiresAt: body.expires_at,
    isThisOne: body.is_this_one,
  };
}
