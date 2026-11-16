import { render, screen } from "@testing-library/react";
import { afterEach, describe, expect, it, vi } from "vitest";
import { DataTable } from "@/components/data-table";

function stubMatchMedia(matches: boolean) {
  vi.stubGlobal("matchMedia", (query: string): MediaQueryList => ({
    matches,
    media: query,
    onchange: null,
    addListener: () => {},
    removeListener: () => {},
    addEventListener: () => {},
    removeEventListener: () => {},
    dispatchEvent: () => false,
  }));
}

afterEach(() => {
  vi.unstubAllGlobals();
});

describe("DataTable", () => {
  it("renders the empty-state message when there are no rows", () => {
    stubMatchMedia(false);
    render(
      <DataTable
        caption="Things"
        headers={["Name"]}
        rows={[]}
        emptyMessage="Nothing here."
      />,
    );
    expect(screen.getByRole("status")).toHaveTextContent("Nothing here.");
  });

  it("renders a real table at wide viewports", () => {
    stubMatchMedia(false);
    render(
      <DataTable
        caption="Things"
        headers={["Name"]}
        rows={[{ key: "1", cells: ["Alpha"] }]}
        emptyMessage="Nothing here."
      />,
    );
    expect(screen.getByRole("table", { name: "Things" })).toBeVisible();
    expect(screen.queryByRole("list")).not.toBeInTheDocument();
  });

  it("stays a table at narrow viewports, scrolling sideways", () => {
    // The design keeps tables on a phone; cards were the old layout.
    stubMatchMedia(true);
    render(
      <DataTable
        caption="Things"
        headers={["Name"]}
        rows={[{ key: "1", cells: ["Alpha"] }]}
        emptyMessage="Nothing here."
      />,
    );
    expect(screen.getByRole("table", { name: "Things" })).toBeVisible();
  });
});
