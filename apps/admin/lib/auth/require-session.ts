import "server-only";
import { headers } from "next/headers";
import { redirect } from "next/navigation";
import { getAdminSession } from "./session";
import type { AdminSession } from "./types";

/** Redirects to `/login?reason=expired` when there is no valid admin session. */
export async function requireAdminSession(): Promise<AdminSession> {
  const session = await getAdminSession();
  if (session === null) {
    // The proxy passes on the page asked for, so sign-in can return to it.
    const path = (await headers()).get("x-nebula-path");
    redirect(
      path
        ? `/login?reason=expired&next=${encodeURIComponent(path)}`
        : "/login?reason=expired",
    );
  }
  return session;
}
