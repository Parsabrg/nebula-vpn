import type { SecurityCheck } from "@/lib/security";
import type { VpnServerHealthItem } from "@/lib/topology";

/**
 * Overview's "Needs attention": what the Servers, Security and Email pages
 * already report as wrong, gathered in one card. Nothing new is measured.
 *
 * Behind NEBULA_ADMIN_NEEDS_ATTENTION (on unless set to "off") while it is an
 * open product decision (DESIGN_SPEC section 7, item 2).
 */
export interface AttentionItem {
  text: string;
  href: string;
  /** The page that shows and fixes it, for the card's Where column. */
  where: string;
  tone: "warning" | "danger";
}

export function needsAttentionEnabled(
  env: Record<string, string | undefined> = process.env,
): boolean {
  return env.NEBULA_ADMIN_NEEDS_ATTENTION !== "off";
}

export function attentionItems(
  health: readonly VpnServerHealthItem[],
  checks: readonly SecurityCheck[],
  failedEmails: number,
): AttentionItem[] {
  const items: AttentionItem[] = [];
  for (const server of health) {
    if (server.state === "degraded" || server.state === "unreachable") {
      items.push({
        text: `${server.code}: ${server.state}`,
        href: "/server-health",
        where: "Servers",
        tone: server.state === "unreachable" ? "danger" : "warning",
      });
    }
  }
  for (const check of checks) {
    if (check.status === "warning" || check.status === "failing") {
      items.push({
        text: `${check.label}: ${check.detail}`,
        href: "/security",
        where: "Security",
        tone: check.status === "failing" ? "danger" : "warning",
      });
    }
  }
  if (failedEmails > 0) {
    items.push({
      text:
        failedEmails === 1
          ? "1 email could not be delivered"
          : `${failedEmails} emails could not be delivered`,
      href: "/email-deliveries?state=failed",
      where: "Email",
      tone: "danger",
    });
  }
  return items;
}
