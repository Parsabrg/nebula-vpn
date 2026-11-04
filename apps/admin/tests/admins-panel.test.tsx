import { render, screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";
import { AdminsPanel } from "@/components/admins-panel";
import type { AdminItem } from "@/lib/admins-shape";
import { toAdminItem, toAdminSession } from "@/lib/admins-shape";

const actions = vi.hoisted(() => ({
  inviteAdmin: vi.fn(),
  changeAdminRole: vi.fn(),
  setAdminDisabled: vi.fn(),
  loadAdminSessions: vi.fn(),
  endAdminSession: vi.fn(),
  endAllAdminSessions: vi.fn(),
}));
vi.mock("@/lib/admins-actions", () => actions);

const me: AdminItem = {
  id: "me",
  email: "owner@x.test",
  username: null,
  role: "owner",
  state: "active",
  hasAuthenticator: true,
  createdAt: "2026-11-01T10:00:00Z",
  disabledAt: null,
  isYou: true,
};
const ops: AdminItem = {
  ...me,
  id: "ops",
  email: "ops@x.test",
  role: "operator",
  hasAuthenticator: false,
  isYou: false,
};

function row(email: string) {
  return screen.getByText(email).closest("li") as HTMLElement;
}

describe("AdminsPanel", () => {
  it("offers no actions on your own account", () => {
    render(<AdminsPanel initial={[me, ops]} />);
    expect(within(row("owner@x.test")).queryByRole("button")).toBeNull();
    expect(
      within(row("ops@x.test")).getByText("Has not signed in yet"),
    ).toBeTruthy();
  });

  it("adds an admin and shows the one-time password", async () => {
    actions.inviteAdmin.mockResolvedValue({
      ok: true,
      data: {
        admin: { ...ops, id: "new", email: "new@x.test" },
        temporaryPassword: "pw-canary",
      },
    });
    const user = userEvent.setup();
    render(<AdminsPanel initial={[me]} />);
    await user.click(screen.getByRole("button", { name: "Add an admin" }));
    await user.type(screen.getByLabelText("Email"), "new@x.test");
    await user.selectOptions(screen.getByLabelText("Role"), "auditor");
    await user.click(screen.getByRole("button", { name: "Add" }));

    expect(actions.inviteAdmin).toHaveBeenCalledWith({
      email: "new@x.test",
      username: "",
      role: "auditor",
    });
    expect(screen.getByText("pw-canary")).toBeTruthy();
    expect(screen.getAllByText("new@x.test").length).toBeGreaterThan(0);
    await user.click(screen.getByRole("button", { name: "Done" }));
    expect(screen.queryByText("pw-canary")).toBeNull();
  });

  it("changes a role and disables", async () => {
    actions.changeAdminRole.mockResolvedValue({
      ok: true,
      data: { ...ops, role: "auditor" },
    });
    actions.setAdminDisabled.mockResolvedValue({
      ok: true,
      data: { ...ops, state: "disabled" },
    });
    const user = userEvent.setup();
    render(<AdminsPanel initial={[ops]} />);

    await user.click(screen.getByRole("button", { name: "Change role" }));
    await user.click(screen.getByLabelText(/Auditor/));
    await user.click(screen.getByRole("button", { name: "Save role" }));
    expect(actions.changeAdminRole).toHaveBeenCalledWith("ops", "auditor");

    await user.click(screen.getByRole("button", { name: "Disable" }));
    await user.click(
      within(screen.getByRole("dialog")).getByRole("button", {
        name: "Disable",
      }),
    );
    expect(actions.setAdminDisabled).toHaveBeenCalledWith("ops", true);
    expect(
      await screen.findByRole("button", { name: "Reactivate" }),
    ).toBeTruthy();
  });

  it("lists sessions and ends them", async () => {
    actions.loadAdminSessions.mockResolvedValue({
      ok: true,
      data: [
        {
          sessionId: "s1",
          mfaMethod: "recovery",
          createdAt: "2026-11-04T08:00:00Z",
          lastSeenAt: "2026-11-04T09:00:00Z",
          expiresAt: "2026-11-04T16:00:00Z",
          isThisOne: false,
        },
      ],
    });
    actions.endAdminSession.mockResolvedValue({ ok: true, data: null });
    const user = userEvent.setup();
    render(<AdminsPanel initial={[ops]} />);

    await user.click(screen.getByRole("button", { name: "Sessions" }));
    expect(await screen.findByText(/recovery code/)).toBeTruthy();
    await user.click(screen.getByRole("button", { name: "End" }));
    await user.click(screen.getByRole("button", { name: "End session" }));
    expect(actions.endAdminSession).toHaveBeenCalledWith("ops", "s1");
    expect(await screen.findByText("No live sessions.")).toBeTruthy();
  });

  it("says why sessions did not load", async () => {
    actions.loadAdminSessions.mockResolvedValue({
      ok: false,
      code: "unknown",
      message: "Admin management is temporarily unavailable",
    });
    const user = userEvent.setup();
    render(<AdminsPanel initial={[ops]} />);
    await user.click(screen.getByRole("button", { name: "Sessions" }));
    expect(await screen.findByRole("alert")).toBeTruthy();
  });

  it("maps the API's shapes", () => {
    expect(
      toAdminItem({
        id: "a",
        email: "e",
        username: null,
        role: "auditor",
        state: "active",
        has_authenticator: true,
        created_at: "c",
        disabled_at: null,
        is_you: false,
      }).hasAuthenticator,
    ).toBe(true);
    expect(
      toAdminSession({
        session_id: "s",
        mfa_method: "totp",
        created_at: "c",
        last_seen_at: "l",
        expires_at: "x",
        is_this_one: true,
      }).isThisOne,
    ).toBe(true);
  });
});
