"use client";

import Link, { useLinkStatus } from "next/link";
import { usePathname } from "next/navigation";

const navigation = [
  { href: "/", label: "Overview" },
  { href: "/requests", label: "Requests" },
  { href: "/users", label: "Users" },
  { href: "/server-health", label: "Servers" },
  { href: "/permissions", label: "Permissions" },
  { href: "/assignments", label: "Assignments" },
  { href: "/audit-log", label: "Audit log" },
  { href: "/email-deliveries", label: "Email" },
  { href: "/security", label: "Security" },
  { href: "/pair-device", label: "Pair a device" },
] as const;

/** Whether [href] is the section the viewer is in ("/users/x" is Users). */
export function isCurrent(pathname: string, href: string): boolean {
  return href === "/"
    ? pathname === "/"
    : pathname === href || pathname.startsWith(`${href}/`);
}

/** The menu, with the current section marked: nothing showing where you
 * were was one of the sweep's findings (2026-11-01). */
export function NavLinks() {
  const pathname = usePathname() ?? "/";
  return (
    <ul className="nav-list">
      {navigation.map((item) => (
        <li key={item.href}>
          <Link
            href={item.href}
            aria-current={isCurrent(pathname, item.href) ? "page" : undefined}
          >
            {item.label}
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
