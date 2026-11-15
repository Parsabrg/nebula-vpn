"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useEffect, useRef, useState, type ReactNode } from "react";
import type { AdminRole } from "@/lib/auth/types";
import { LogoutButton } from "./logout-button";
import { NavLinks } from "./nav-links";

/**
 * The frame every signed-in page sits in (DESIGN_SPEC section 5): a 56 px
 * header with the brand, the role and Sign out; a 232 px sidebar with the
 * sections; the page capped at 1080 px. Below 900 px the sidebar is a drawer
 * behind the Menu button, which Escape, a chosen link or the backdrop close.
 */
export function AdminShell({
  role,
  pendingRequests = 0,
  children,
}: Readonly<{
  role: AdminRole;
  pendingRequests?: number;
  children: ReactNode;
}>) {
  const [open, setOpen] = useState(false);
  const menuButton = useRef<HTMLButtonElement>(null);
  const nav = useRef<HTMLElement>(null);
  const pathname = usePathname();

  // A link chosen in the drawer is a page change: the drawer has done its job.
  const [shownPath, setShownPath] = useState(pathname);
  if (shownPath !== pathname) {
    setShownPath(pathname);
    setOpen(false);
  }

  useEffect(() => {
    if (!open) {
      return;
    }
    nav.current?.querySelector<HTMLElement>("a")?.focus();
    const onKey = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        setOpen(false);
        menuButton.current?.focus();
      }
    };
    document.addEventListener("keydown", onKey);
    return () => document.removeEventListener("keydown", onKey);
  }, [open]);

  return (
    <div className="admin-shell" data-nav-open={open ? "true" : undefined}>
      <header className="admin-header">
        <button
          ref={menuButton}
          type="button"
          className="admin-header__menu"
          aria-expanded={open}
          aria-controls="admin-nav"
          onClick={() => setOpen((was) => !was)}
        >
          <span aria-hidden="true" className="admin-header__menu-icon" />
          Menu
        </button>
        <Link
          className="brand"
          href="/"
          aria-label="Nebula administration overview"
        >
          <span className="brand__mark">NEBULA</span>
          <small>Administration</small>
        </Link>
        <div className="admin-header__account">
          <span className="badge badge--role" aria-label="Signed in role">
            {role}
          </span>
          <LogoutButton />
        </div>
      </header>
      <div className="admin-shell__body">
        <nav
          ref={nav}
          id="admin-nav"
          className="admin-nav"
          aria-label="Primary navigation"
        >
          <NavLinks pendingRequests={pendingRequests} />
        </nav>
        {open ? (
          <div
            className="admin-shell__backdrop"
            aria-hidden="true"
            onClick={() => setOpen(false)}
          />
        ) : null}
        <main id="main-content" className="page-shell" tabIndex={-1}>
          {children}
        </main>
      </div>
    </div>
  );
}
