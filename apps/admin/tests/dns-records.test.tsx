import { render, screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { DnsRecordsView } from "@/components/dns-records";

const checkDnsRecords = vi.hoisted(() => vi.fn());
vi.mock("@/lib/topology-actions", () => ({ checkDnsRecords }));

const panel = {
  name: "panel.example.org",
  type: "A",
  value: "198.51.100.7",
  purpose: "control-plane",
  proxied: false,
  ok: true,
  found: ["198.51.100.7"],
  detail: "panel.example.org → 198.51.100.7",
};
const cdn = {
  name: "cdn.example.org",
  type: "A",
  value: "198.51.100.7",
  purpose: "cdn",
  proxied: true,
  ok: false,
  found: ["198.51.100.7"],
  detail: "points straight at the server: turn the CDN proxy on",
};

describe("DnsRecordsView", () => {
  beforeEach(() => checkDnsRecords.mockReset());

  it("puts what needs fixing first, then says all is in place once fixed", async () => {
    checkDnsRecords
      .mockResolvedValueOnce({ ok: true, data: [panel, cdn] })
      .mockResolvedValueOnce({
        ok: true,
        data: [panel, { ...cdn, ok: true, detail: "goes through the CDN" }],
      });
    render(<DnsRecordsView />);

    expect(
      await screen.findByText("1 of 2 need fixing at your DNS provider."),
    ).toBeInTheDocument();
    const first = screen.getAllByRole("row")[1]!;
    expect(within(first).getByText("cdn.example.org")).toBeInTheDocument();
    expect(within(first).getByText("✗ Fix")).toBeInTheDocument();
    expect(within(first).getByText("Proxied")).toBeInTheDocument();
    expect(within(first).getByText("CDN route")).toBeInTheDocument();
    expect(
      screen.getByRole("button", { name: "Copy records to fix" }),
    ).toBeInTheDocument();

    await userEvent.click(screen.getByRole("button", { name: "Check again" }));
    expect(
      await screen.findByText("Every record is in place."),
    ).toBeInTheDocument();
    expect(
      screen.queryByRole("button", { name: "Copy records to fix" }),
    ).not.toBeInTheDocument();
  });

  it("shows an error it could not check", async () => {
    checkDnsRecords.mockResolvedValueOnce({
      ok: false,
      message: "The API did not answer.",
    });
    render(<DnsRecordsView />);
    expect(await screen.findByRole("alert")).toHaveTextContent(
      "The API did not answer.",
    );
  });
});
