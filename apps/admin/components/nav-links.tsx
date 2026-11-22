"use client";

import Link, { useLinkStatus } from "next/link";
import { usePathname } from "next/navigation";

/** The sections, each with its icon (Material Icons Outlined names), as the
 * design draws the sidebar. */
const navigation = [
  { href: "/", label: "Overview", icon: "dashboard" },
  { href: "/requests", label: "Requests", icon: "inbox" },
  { href: "/users", label: "Users", icon: "group" },
  { href: "/server-health", label: "Servers", icon: "dns" },
  { href: "/permissions", label: "Permissions", icon: "verified_user" },
  { href: "/assignments", label: "Assignments", icon: "link" },
  { href: "/audit-log", label: "Audit log", icon: "history" },
  { href: "/email-deliveries", label: "Email", icon: "mail" },
  { href: "/security", label: "Security", icon: "shield" },
  { href: "/admins", label: "Admins", icon: "admin_panel_settings" },
  { href: "/pair-device", label: "Pair a device", icon: "qr_code_2" },
  { href: "/appearance", label: "Appearance", icon: "palette" },
] as const;

/** Whether [href] is the section the viewer is in ("/users/x" is Users). */
export function isCurrent(pathname: string, href: string): boolean {
  return href === "/"
    ? pathname === "/"
    : pathname === href || pathname.startsWith(`${href}/`);
}

/** The menu, with the current section marked: nothing showing where you
 * were was one of the sweep's findings. Requests carries the
 * number waiting, so it shows from any page. */
export function NavLinks({
  pendingRequests = 0,
}: Readonly<{ pendingRequests?: number }>) {
  const pathname = usePathname() ?? "/";
  return (
    <ul className="nav-list">
      {navigation.map((item) => (
        <li key={item.href}>
          <Link
            href={item.href}
            aria-current={isCurrent(pathname, item.href) ? "page" : undefined}
          >
            <span className="nav-icon" aria-hidden="true">
              {item.icon}
            </span>
            <span className="nav-label">{item.label}</span>
            {item.href === "/requests" && pendingRequests > 0 ? (
              <span
                className="nav-count"
                aria-label={`${pendingRequests} pending`}
              >
                {pendingRequests}
              </span>
            ) : null}
            <Pending />
          </Link>
        </li>
      ))}
    </ul>
  );
}

/** Shown on the link just clicked while its page loads: a slow page then
 * reads as "on its way", never as a click that did nothing. */
function Pending() {
  const { pending } = useLinkStatus();
  return pending ? <span className="nav-pending" aria-hidden="true" /> : null;
}
