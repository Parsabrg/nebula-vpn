import { describe, expect, it } from "vitest";
import { safeReturnPath } from "@/lib/end-session";

describe("the page to return to after sign-in", () => {
  it("keeps a page of this panel", () => {
    expect(safeReturnPath("/users/abc?x=1")).toBe("/users/abc?x=1");
  });

  it("refuses anything that could leave the panel or loop", () => {
    for (const value of [
      null,
      "",
      "https://evil.example",
      "//evil.example",
      "/\\evil.example",
      "/login",
      "/login?reason=expired",
      "/api/admin/auth/logout",
    ]) {
      expect(safeReturnPath(value)).toBe("/");
    }
  });
});
