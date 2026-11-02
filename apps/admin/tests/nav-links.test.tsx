import { render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import { NavLinks, isCurrent } from "@/components/nav-links";

const pathname = vi.hoisted(() => ({ value: "/users/abc" }));
vi.mock("next/navigation", () => ({ usePathname: () => pathname.value }));

describe("the menu", () => {
  it("marks the section of the page you are on", () => {
    render(<NavLinks />);

    expect(screen.getByRole("link", { name: "Users" })).toHaveAttribute(
      "aria-current",
      "page",
    );
    expect(screen.getByRole("link", { name: "Overview" })).not.toHaveAttribute(
      "aria-current",
    );
  });

  it("matches whole sections, not prefixes", () => {
    expect(isCurrent("/", "/")).toBe(true);
    expect(isCurrent("/users", "/")).toBe(false);
    expect(isCurrent("/server-health/add", "/server-health")).toBe(true);
    expect(isCurrent("/users-old", "/users")).toBe(false);
  });
});
