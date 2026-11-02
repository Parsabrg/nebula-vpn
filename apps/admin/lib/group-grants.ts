import type { PermissionListItem } from "./access";

export interface UserGrants {
  userId: string;
  userEmail: string;
  enabled: string[];
  other: number;
}

/** One entry per user, in the order the rows came. */
export function groupByUser(items: PermissionListItem[]): UserGrants[] {
  const groups: UserGrants[] = [];
  for (const item of items) {
    let group = groups.at(-1);
    if (group?.userId !== item.userId) {
      group = {
        userId: item.userId,
        userEmail: item.userEmail,
        enabled: [],
        other: 0,
      };
      groups.push(group);
    }
    if (item.state === "enabled") group.enabled.push(item.profileDisplayName);
    else group.other += 1;
  }
  return groups;
}
