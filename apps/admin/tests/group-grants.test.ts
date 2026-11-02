import { describe, expect, it } from "vitest";
import type { PermissionListItem } from "@/lib/access";
import { groupByUser } from "@/lib/group-grants";

function grant(
  userId: string,
  profileDisplayName: string,
  state = "enabled",
): PermissionListItem {
  return {
    userId,
    userEmail: `${userId}@x.test`,
    profileDisplayName,
    state,
  } as PermissionListItem;
}

describe("groupByUser", () => {
  it("puts each user's grants on one line, counting the ones not in use", () => {
    expect(
      groupByUser([
        grant("a", "VLESS"),
        grant("a", "WireGuard"),
        grant("a", "Hysteria2", "revoked"),
        grant("b", "VLESS"),
      ]),
    ).toEqual([
      {
        userId: "a",
        userEmail: "a@x.test",
        enabled: ["VLESS", "WireGuard"],
        other: 1,
      },
      { userId: "b", userEmail: "b@x.test", enabled: ["VLESS"], other: 0 },
    ]);
  });
});
