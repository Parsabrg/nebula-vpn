import "server-only";
import { apiFetch } from "@/lib/api/client";

export type AccountRequestState =
  "pending" | "approved" | "rejected" | "expired";

export interface AccountRequestListItem {
  id: string;
  email: string;
  username: string | null;
  state: AccountRequestState;
  createdAt: string;
  /** What an existing account already has: approving would be refused. */
  taken: ("email" | "username")[];
}

interface AccountRequestItemBody {
  id: string;
  email: string;
  username: string | null;
  state: AccountRequestState;
  created_at: string;
  taken?: ("email" | "username")[];
}

interface AccountRequestListResponseBody {
  items: AccountRequestItemBody[];
}

function toItem(body: AccountRequestItemBody): AccountRequestListItem {
  return {
    id: body.id,
    email: body.email,
    username: body.username,
    state: body.state,
    createdAt: body.created_at,
    taken: body.taken ?? [],
  };
}

export async function listPendingAccountRequests(): Promise<
  AccountRequestListItem[]
> {
  const body = await apiFetch<AccountRequestListResponseBody>(
    "/v1/admin/account-requests/",
  );
  return body.items.map(toItem);
}
