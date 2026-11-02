import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";
import { MutationButton } from "@/components/mutation-button";

vi.mock("@/components/step-up-modal", () => ({
  StepUpModal: ({
    open,
    onVerified,
  }: {
    open: boolean;
    onVerified: () => void;
  }) =>
    open ? (
      <button type="button" onClick={onVerified}>
        Verify code
      </button>
    ) : null,
}));

describe("MutationButton", () => {
  it("shows why an action was refused after the code was asked for", async () => {
    const action = vi
      .fn()
      .mockResolvedValueOnce({
        ok: false,
        code: "step_up_required",
        message: "",
      })
      .mockResolvedValueOnce({
        ok: false,
        code: "conflict",
        message: "Another account already uses that email.",
      });
    const user = userEvent.setup();
    render(
      <MutationButton
        triggerLabel="Edit"
        triggerClassName="button"
        confirmTitle="Edit"
        confirmLabel="Save"
        confirmBody={<p>Body</p>}
        action={action}
        onSuccess={vi.fn()}
      />,
    );

    await user.click(screen.getByRole("button", { name: "Edit" }));
    await user.click(screen.getByRole("button", { name: "Save" }));
    await user.click(
      await screen.findByRole("button", { name: "Verify code" }),
    );

    const alert = await screen.findByRole("alert");
    expect(alert).toHaveTextContent("Another account already uses that email.");
    expect(alert.closest("dialog")).toHaveAttribute("open");
  });
});
