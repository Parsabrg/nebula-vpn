import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { DnsTunnelStatusView } from "@/components/dns-tunnel-status";

const checkDnsTunnel = vi.hoisted(() => vi.fn());
vi.mock("@/lib/topology-actions", () => ({ checkDnsTunnel }));

const records = [
  { name: "t2.example.org", type: "NS", value: "ns-t2.example.org" },
  { name: "ns-t2.example.org", type: "A", value: "203.0.113.20" },
];

describe("DnsTunnelStatusView", () => {
  beforeEach(() => checkDnsTunnel.mockReset());

  it("lists the records to add until the name works, then says so", async () => {
    checkDnsTunnel
      .mockResolvedValueOnce({
        ok: true,
        data: {
          serverIp: "203.0.113.20",
          records,
          checks: [
            {
              key: "delegated",
              ok: false,
              detail: "t2.example.org has no NS record yet",
            },
            { key: "answers", ok: false, detail: "nothing answers on port 53" },
          ],
        },
      })
      .mockResolvedValueOnce({
        ok: true,
        data: {
          serverIp: "203.0.113.20",
          records,
          checks: [
            { key: "delegated", ok: true, detail: "delegated" },
            {
              key: "answers",
              ok: true,
              detail: "the tunnel answers on port 53",
            },
          ],
        },
      });
    const user = userEvent.setup();
    render(<DnsTunnelStatusView serverId="s1" />);

    expect(
      await screen.findAllByText("ns-t2.example.org", { selector: "td" }),
    ).toHaveLength(2);
    expect(screen.getByText(/has no NS record yet/)).toBeVisible();
    expect(screen.getByRole("button", { name: "Copy records" })).toBeVisible();

    await user.click(screen.getByRole("button", { name: "Check again" }));

    expect(
      await screen.findByText(/apps on this server can use the DNS tunnel/),
    ).toBeVisible();
    expect(screen.queryByRole("table")).toBeNull();
    expect(checkDnsTunnel).toHaveBeenCalledTimes(2);
  });

  it("says why it could not check", async () => {
    checkDnsTunnel.mockResolvedValueOnce({
      ok: false,
      code: "not_found",
      message: "No DNS tunnel",
    });
    render(<DnsTunnelStatusView serverId="s1" />);
    expect(await screen.findByRole("alert")).toHaveTextContent("No DNS tunnel");
  });
});
