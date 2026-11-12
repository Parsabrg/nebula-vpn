import { isIP } from "node:net";

/**
 * The administrator's address for the API's rate limits. nginx sets
 * X-Real-IP to the peer it accepted the connection from (overwriting any
 * the browser sent); passed on as X-Forwarded-For, which the API trusts
 * from this container only (FORWARDED_ALLOW_IPS in production.yaml).
 * Without it every admin shared one bucket, and five requests from anyone
 * locked them all out (audit AUD-002). Anything but an address is dropped.
 */
export function forwardedClient(realIp: string | null): string | null {
  const value = realIp?.trim() ?? "";
  return isIP(value) ? value : null;
}
