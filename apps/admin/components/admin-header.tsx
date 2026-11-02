import Link from "next/link";
import type { AdminSession } from "@/lib/auth/types";
import { LogoutButton } from "./logout-button";
import { NavLinks } from "./nav-links";

export function AdminHeader({ session }: { session: AdminSession }) {
  return (
    <header className="site-header">
      <div className="site-header__inner">
        <Link
          className="brand"
          href="/"
          aria-label="Nebula administration overview"
        >
          <span>
            <span className="brand__mark">NEBULA</span>
            <small>Administration</small>
          </span>
        </Link>
        <nav aria-label="Primary navigation">
          <NavLinks />
        </nav>
        <div className="admin-header__account">
          <span className="badge badge--role" aria-label="Signed in role">
            {session.role}
          </span>
          <LogoutButton />
        </div>
      </div>
    </header>
  );
}
