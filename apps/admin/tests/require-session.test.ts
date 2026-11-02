import { afterEach, describe, expect, it, vi } from "vitest";

const redirectMock = vi.fn((url: string) => {
  throw new Error(`REDIRECT:${url}`);
});
vi.mock("next/navigation", () => ({
  redirect: redirectMock,
}));

const pathHeader = vi.hoisted(() => ({ value: "/users/abc" as string | null }));
vi.mock("next/headers", () => ({
  headers: async () =>
    new Headers(pathHeader.value ? { "x-nebula-path": pathHeader.value } : {}),
}));

const getAdminSessionMock = vi.fn();
vi.mock("@/lib/auth/session", () => ({
  getAdminSession: getAdminSessionMock,
}));

afterEach(() => {
  vi.clearAllMocks();
});

describe("requireAdminSession", () => {
  it("redirects to sign-in, naming the page to come back to", async () => {
    getAdminSessionMock.mockResolvedValue(null);
    pathHeader.value = "/users/abc";
    const { requireAdminSession } = await import("@/lib/auth/require-session");

    await expect(requireAdminSession()).rejects.toThrow("REDIRECT:");
    expect(redirectMock).toHaveBeenCalledWith(
      "/login?reason=expired&next=%2Fusers%2Fabc",
    );
  });

  it("redirects to plain sign-in when the page is not known", async () => {
    getAdminSessionMock.mockResolvedValue(null);
    pathHeader.value = null;
    const { requireAdminSession } = await import("@/lib/auth/require-session");

    await expect(requireAdminSession()).rejects.toThrow("REDIRECT:");
    expect(redirectMock).toHaveBeenCalledWith("/login?reason=expired");
  });

  it("returns the session and does not redirect when one exists", async () => {
    const session = { adminId: "1", role: "owner" as const, stepUp: false };
    getAdminSessionMock.mockResolvedValue(session);
    const { requireAdminSession } = await import("@/lib/auth/require-session");

    await expect(requireAdminSession()).resolves.toEqual(session);
    expect(redirectMock).not.toHaveBeenCalled();
  });
});
