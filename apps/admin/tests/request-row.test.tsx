import { render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import { RequestRow } from "@/components/request-row";

vi.mock("@/lib/account-requests-actions", () => ({
  approveAccountRequest: vi.fn(),
  rejectAccountRequest: vi.fn(),
}));

const request = {
  id: "r",
  email: "a@x.test",
  username: "ali",
  state: "pending" as const,
  createdAt: "2026-11-01T07:00:00Z",
};

function renderRow(taken: ("email" | "username")[]) {
  render(
    <table>
      <tbody>
        <RequestRow request={{ ...request, taken }} />
      </tbody>
    </table>,
  );
}

describe("RequestRow", () => {
  it("says up front when an existing account has the username", () => {
    renderRow(["username"]);
    expect(
      screen.getByText("Another account has this username."),
    ).toBeInTheDocument();
    expect(screen.queryByText(/already uses this email/)).toBeNull();
  });

  it("says nothing when there is no clash", () => {
    renderRow([]);
    expect(screen.queryByText(/already|Another account/)).toBeNull();
  });
});
