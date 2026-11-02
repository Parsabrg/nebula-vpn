import { describe, expect, it } from "vitest";
import { extendBy } from "@/components/expiry-control";

const now = new Date(2026, 0, 31, 9, 30);

describe("expiry quick choices", () => {
  it("counts from now when there is no expiry or it has passed", () => {
    expect(extendBy(null, 1, now)).toBe("2026-02-28T09:30");
    expect(extendBy(new Date(2025, 5, 1).toISOString(), 12, now)).toBe(
      "2027-01-31T09:30",
    );
  });

  it("extends a future expiry, keeping its time", () => {
    expect(extendBy(new Date(2026, 2, 15, 12, 0).toISOString(), 3, now)).toBe(
      "2026-06-15T12:00",
    );
  });
});
