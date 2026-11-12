import { describe, expect, it } from "vitest";
import { forwardedClient } from "@/lib/api/forwarded-client";

describe("forwardedClient", () => {
  it("passes on an address nginx gave", () => {
    expect(forwardedClient("203.0.113.7")).toBe("203.0.113.7");
    expect(forwardedClient(" 2001:db8::1 ")).toBe("2001:db8::1");
  });

  it("drops anything that is not one address", () => {
    expect(forwardedClient(null)).toBeNull();
    expect(forwardedClient("")).toBeNull();
    expect(forwardedClient("1.2.3.4, 5.6.7.8")).toBeNull();
    expect(forwardedClient("evil")).toBeNull();
  });
});
