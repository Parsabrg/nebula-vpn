import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";
import { UserAccountActions } from "@/components/user-account-actions";

const push = vi.fn();
vi.mock("next/navigation", () => ({
  useRouter: () => ({ push, refresh: vi.fn() }),
}));

const actions = vi.hoisted(() => ({
  deleteUser: vi.fn(),
  reissueActivation: vi.fn(),
}));
vi.mock("@/lib/users-actions", () => actions);

describe("UserAccountActions", () => {
  it("offers the activation email only to an account that never activated", () => {
    const { rerender } = render(
      <UserAccountActions userId="u" email="a@x.test" state="active" />,
    );
    expect(
      screen.queryByRole("button", { name: "Send activation email again" }),
    ).toBeNull();

    rerender(
      <UserAccountActions
        userId="u"
        email="a@x.test"
        state="pending_activation"
      />,
    );
    expect(
      screen.getByRole("button", { name: "Send activation email again" }),
    ).toBeInTheDocument();
  });

  it("deletes after confirming, then returns to the user list", async () => {
    actions.deleteUser.mockResolvedValue({ ok: true, data: null });
    const user = userEvent.setup();
    render(<UserAccountActions userId="u" email="a@x.test" state="active" />);

    await user.click(screen.getByRole("button", { name: "Delete user" }));
    expect(actions.deleteUser).not.toHaveBeenCalled();
    await user.click(screen.getByRole("button", { name: "Delete" }));

    expect(actions.deleteUser).toHaveBeenCalledWith("u");
    expect(push).toHaveBeenCalledWith("/users");
  });
});
