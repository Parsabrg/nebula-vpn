import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, describe, expect, it, vi } from "vitest";
import {
  ChangeOwnPassword,
  ReplaceOwnAuthenticator,
} from "@/components/own-sign-in";

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

function reply(status: number, body: unknown) {
  return Promise.resolve(
    new Response(JSON.stringify(body), {
      status,
      headers: { "Content-Type": "application/json" },
    }),
  );
}

afterEach(() => vi.unstubAllGlobals());

describe("ChangeOwnPassword", () => {
  async function fill(
    user: ReturnType<typeof userEvent.setup>,
    repeat: string,
  ) {
    await user.type(screen.getByLabelText("Current password"), "old-one");
    await user.type(screen.getByLabelText("New password"), "a-new-password");
    await user.type(screen.getByLabelText("New password again"), repeat);
    await user.click(screen.getByRole("button", { name: "Change password" }));
  }

  it("asks for a code, then changes the password", async () => {
    const fetchMock = vi
      .fn()
      .mockImplementationOnce(() => reply(403, { detail: "step_up_required" }))
      .mockImplementationOnce(() => reply(200, { step_up: true }));
    vi.stubGlobal("fetch", fetchMock);
    const user = userEvent.setup();
    render(<ChangeOwnPassword />);

    await fill(user, "a-new-password");
    const verify = await screen.findByRole("button", { name: "Verify code" });
    // The code dialog has its own form; nested in this one, the browser
    // submitted this form with the code in the address bar.
    expect(verify.closest("form")).toBeNull();
    await user.click(verify);

    expect(await screen.findByRole("status")).toHaveTextContent(
      "Password changed",
    );
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  it("says why it was refused", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn(() => reply(409, { detail: "The current password is not right." })),
    );
    const user = userEvent.setup();
    render(<ChangeOwnPassword />);

    await fill(user, "a-new-password");

    expect(await screen.findByRole("alert")).toHaveTextContent(
      "The current password is not right.",
    );
  });

  it("catches a mistyped repeat before sending", async () => {
    const fetchMock = vi.fn();
    vi.stubGlobal("fetch", fetchMock);
    const user = userEvent.setup();
    render(<ChangeOwnPassword />);

    await fill(user, "something-else");

    expect(screen.getByRole("alert")).toHaveTextContent("not the same");
    expect(fetchMock).not.toHaveBeenCalled();
  });
});

describe("ReplaceOwnAuthenticator", () => {
  it("shows the new code to scan, then the new recovery codes", async () => {
    vi.stubGlobal(
      "fetch",
      vi
        .fn()
        .mockImplementationOnce(() =>
          reply(200, {
            secret: "NEWKEY",
            provisioning_uri: "otpauth://totp/x",
            qr_svg: '<svg xmlns="http://www.w3.org/2000/svg"></svg>',
          }),
        )
        .mockImplementationOnce(() =>
          reply(200, { recovery_codes: ["v1.one", "v1.two"] }),
        ),
    );
    const user = userEvent.setup();
    render(<ReplaceOwnAuthenticator />);

    await user.click(
      screen.getByRole("button", { name: "Set up a new authenticator" }),
    );
    expect(await screen.findByText("NEWKEY")).toBeInTheDocument();
    await user.type(
      screen.getByLabelText("Code from the new authenticator"),
      "123456",
    );
    await user.click(
      screen.getByRole("button", { name: "Use the new authenticator" }),
    );

    expect(await screen.findByText("v1.one")).toBeInTheDocument();
  });
});
