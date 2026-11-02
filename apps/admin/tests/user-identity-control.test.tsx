import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";
import { UserIdentityControl } from "@/components/user-identity-control";

const refresh = vi.fn();
vi.mock("next/navigation", () => ({ useRouter: () => ({ refresh }) }));
const changeIdentity = vi.hoisted(() => vi.fn());
vi.mock("@/lib/users-actions", () => ({ changeIdentity }));

describe("UserIdentityControl", () => {
  it("sends only what changed, then shows the new values", async () => {
    changeIdentity.mockResolvedValue({ ok: true, data: {} });
    const user = userEvent.setup();
    render(<UserIdentityControl userId="u" email="a@x.test" username="ali" />);

    await user.click(
      screen.getByRole("button", { name: "Edit email or username" }),
    );
    await user.clear(screen.getByLabelText(/Username/));
    await user.click(screen.getByRole("button", { name: "Save" }));

    expect(changeIdentity).toHaveBeenCalledWith("u", { username: "" });
    expect(refresh).toHaveBeenCalled();
  });
});
