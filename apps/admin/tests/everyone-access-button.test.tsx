import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";
import { ServerForEveryone } from "@/components/everyone-access-button";

const assignServerToEveryone = vi.hoisted(() => vi.fn());
vi.mock("@/lib/access-actions", () => ({
  assignServerToEveryone,
  grantProfileToEveryone: vi.fn(),
}));

describe("ServerForEveryone", () => {
  it("says how many users gained the server", async () => {
    assignServerToEveryone.mockResolvedValue({
      ok: true,
      data: { changed: 4 },
    });
    const user = userEvent.setup();
    render(<ServerForEveryone serverId="s" name="Amsterdam 1" />);

    await user.click(
      screen.getByRole("button", { name: "Give every user this server" }),
    );
    await user.click(screen.getByRole("button", { name: "Give access" }));

    expect(assignServerToEveryone).toHaveBeenCalledWith("s");
    expect(await screen.findByRole("status")).toHaveTextContent(
      "4 users gained access.",
    );
  });
});
