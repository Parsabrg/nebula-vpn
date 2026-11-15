import { describe, expect, it } from "vitest";
import { attentionItems, needsAttentionEnabled } from "@/lib/attention";
import type { SecurityCheck } from "@/lib/security";
import type { VpnServerHealthItem } from "@/lib/topology";

const server = (
  code: string,
  state: VpnServerHealthItem["state"],
): VpnServerHealthItem => ({
  serverId: code,
  code,
  state,
  observedAt: "2026-11-14T00:00:00Z",
  latencyMs: null,
  agentVersion: null,
  interfaceUp: null,
  peerCount: null,
});

const check = (label: string, status: SecurityCheck["status"]) => ({
  key: label,
  label,
  status,
  detail: "detail",
  observedAt: null,
});

describe("needs attention", () => {
  it("gathers only what is wrong, linked to where it is shown", () => {
    const items = attentionItems(
      [server("fra-1", "healthy"), server("ams-1", "unreachable")],
      [check("Backup", "failing"), check("Database", "ok")],
      2,
    );
    expect(items).toEqual([
      {
        text: "ams-1: unreachable",
        href: "/server-health",
        where: "Servers",
        tone: "danger",
      },
      {
        text: "Backup: detail",
        href: "/security",
        where: "Security",
        tone: "danger",
      },
      {
        text: "2 emails could not be delivered",
        href: "/email-deliveries?state=failed",
        where: "Email",
        tone: "danger",
      },
    ]);
  });

  it("is empty when all is well", () => {
    expect(attentionItems([server("fra-1", "healthy")], [], 0)).toEqual([]);
  });

  it("is on unless turned off", () => {
    expect(needsAttentionEnabled({})).toBe(true);
    expect(needsAttentionEnabled({ NEBULA_ADMIN_NEEDS_ATTENTION: "off" })).toBe(
      false,
    );
  });
});
