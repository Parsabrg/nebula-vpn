import { render, screen, waitFor } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { afterEach, describe, expect, it, vi } from "vitest";
import { LoginFlow } from "@/components/login-flow";
import { OwnPasskeys } from "@/components/own-sign-in";
import {
  createPasskey,
  getPasskey,
  PASSKEY_CANCELLED,
  PASSKEYS_UNSUPPORTED,
} from "@/lib/webauthn";

const push = vi.fn();
vi.mock("next/navigation", () => ({
  useRouter: () => ({ push, refresh: vi.fn() }),
}));
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
    new Response(status === 204 ? null : JSON.stringify(body), {
      status,
      headers: { "Content-Type": "application/json" },
    }),
  );
}

/** A browser that can make and use passkeys, answering with [made]. */
function browserWithPasskeys(made: unknown) {
  const credential = { toJSON: () => made };
  vi.stubGlobal("PublicKeyCredential", {
    parseCreationOptionsFromJSON: (o: unknown) => ({ parsed: o }),
    parseRequestOptionsFromJSON: (o: unknown) => ({ parsed: o }),
  });
  const create = vi.fn().mockResolvedValue(credential);
  const get = vi.fn().mockResolvedValue(credential);
  vi.stubGlobal("navigator", { ...navigator, credentials: { create, get } });
  return { create, get };
}

afterEach(() => {
  vi.unstubAllGlobals();
  push.mockClear();
});

describe("webauthn helpers", () => {
  it("say so when the browser has no passkeys", async () => {
    await expect(createPasskey({})).rejects.toThrow(PASSKEYS_UNSUPPORTED);
    await expect(getPasskey({})).rejects.toThrow(PASSKEYS_UNSUPPORTED);
  });

  it("tell a closed prompt from a missing feature", async () => {
    const { get } = browserWithPasskeys({});
    get.mockRejectedValueOnce(new DOMException("closed", "NotAllowedError"));
    await expect(getPasskey({})).rejects.toThrow(PASSKEY_CANCELLED);
    get.mockResolvedValueOnce(null);
    await expect(getPasskey({})).rejects.toThrow(PASSKEY_CANCELLED);
    get.mockRejectedValueOnce(new TypeError("odd"));
    await expect(getPasskey({})).rejects.toThrow(PASSKEYS_UNSUPPORTED);
  });
});

describe("OwnPasskeys", () => {
  it("asks for a code, then adds a passkey", async () => {
    const { create } = browserWithPasskeys({ id: "made" });
    const fetchMock = vi
      .fn()
      .mockReturnValueOnce(reply(403, { detail: "step_up_required" }))
      .mockReturnValueOnce(reply(200, { options: { challenge: "c" } }))
      .mockReturnValueOnce(
        reply(200, {
          id: "p1",
          name: "Phone",
          created_at: "2026-11-04T10:00:00Z",
          last_used_at: null,
        }),
      );
    vi.stubGlobal("fetch", fetchMock);
    const user = userEvent.setup();
    render(<OwnPasskeys initial={[]} />);

    await user.type(screen.getByLabelText(/Name for this passkey/), "Phone");
    await user.click(screen.getByRole("button", { name: "Add a passkey" }));
    await user.click(
      await screen.findByRole("button", { name: "Verify code" }),
    );

    expect(await screen.findByText("Phone")).toBeTruthy();
    expect(create).toHaveBeenCalledWith({
      publicKey: { parsed: { challenge: "c" } },
    });
    const sent = JSON.parse(fetchMock.mock.calls[2]![1].body as string);
    expect(sent).toEqual({ name: "Phone", credential: { id: "made" } });
  });

  it("removes one, and says why a change was refused", async () => {
    browserWithPasskeys({});
    const fetchMock = vi
      .fn()
      .mockReturnValueOnce(reply(204, null))
      .mockReturnValueOnce(reply(200, { options: {} }))
      .mockReturnValueOnce(
        reply(409, { detail: "This passkey is already added." }),
      );
    vi.stubGlobal("fetch", fetchMock);
    const user = userEvent.setup();
    render(
      <OwnPasskeys
        initial={[
          {
            id: "p1",
            name: "Laptop",
            createdAt: "2026-11-01T10:00:00Z",
            lastUsedAt: "2026-11-03T10:00:00Z",
          },
        ]}
      />,
    );
    await user.click(screen.getByRole("button", { name: "Remove" }));
    await waitFor(() => expect(screen.queryByText("Laptop")).toBeNull());
    expect(fetchMock.mock.calls[0]![0]).toBe(
      "/api/admin/auth/passkeys/p1/delete",
    );

    await user.click(screen.getByRole("button", { name: "Add a passkey" }));
    expect((await screen.findByRole("alert")).textContent).toContain(
      "already added",
    );
  });

  it("says when the browser prompt was closed", async () => {
    const { create } = browserWithPasskeys({});
    create.mockRejectedValueOnce(new DOMException("x", "NotAllowedError"));
    vi.stubGlobal(
      "fetch",
      vi.fn().mockReturnValue(reply(200, { options: {} })),
    );
    const user = userEvent.setup();
    render(<OwnPasskeys initial={[]} />);
    await user.click(screen.getByRole("button", { name: "Add a passkey" }));
    expect((await screen.findByRole("alert")).textContent).toBe(
      PASSKEY_CANCELLED,
    );
  });
});

describe("LoginFlow with a passkey", () => {
  it("signs in with a passkey in place of the code", async () => {
    const { get } = browserWithPasskeys({ id: "used" });
    const fetchMock = vi
      .fn()
      .mockReturnValueOnce(
        reply(200, { challenge: "v1.c", next_step: "mfa", expires_in: 300 }),
      )
      .mockReturnValueOnce(reply(200, { options: { challenge: "x" } }))
      .mockReturnValueOnce(
        reply(200, { admin_id: "a", role: "owner", step_up: false }),
      );
    vi.stubGlobal("fetch", fetchMock);
    const user = userEvent.setup();
    render(<LoginFlow />);
    await user.type(screen.getByLabelText("Email or username"), "o@x.test");
    await user.type(screen.getByLabelText("Password"), "pw");
    await user.keyboard("{Enter}");
    await user.click(
      await screen.findByRole("button", { name: "Use a passkey instead" }),
    );

    await waitFor(() => expect(push).toHaveBeenCalled());
    expect(get).toHaveBeenCalled();
    expect(fetchMock.mock.calls[2]![0]).toBe(
      "/api/admin/auth/mfa/passkey/verify",
    );
    expect(JSON.parse(fetchMock.mock.calls[2]![1].body as string)).toEqual({
      challenge: "v1.c",
      credential: { id: "used" },
    });
  });

  it("keeps the code when there is no passkey", async () => {
    browserWithPasskeys({});
    vi.stubGlobal(
      "fetch",
      vi
        .fn()
        .mockReturnValueOnce(
          reply(200, { challenge: "v1.c", next_step: "mfa", expires_in: 300 }),
        )
        .mockReturnValueOnce(
          reply(409, {
            detail: "No passkey is set up for this account. Use the code.",
          }),
        ),
    );
    const user = userEvent.setup();
    render(<LoginFlow />);
    await user.type(screen.getByLabelText("Email or username"), "o@x.test");
    await user.type(screen.getByLabelText("Password"), "pw");
    await user.keyboard("{Enter}");
    await user.click(
      await screen.findByRole("button", { name: "Use a passkey instead" }),
    );
    expect((await screen.findByRole("alert")).textContent).toContain(
      "Use the code",
    );
    expect(screen.getByLabelText("Authentication code")).toBeTruthy();
  });
});
