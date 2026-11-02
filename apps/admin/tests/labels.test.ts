import { describe, expect, it } from "vitest";
import { codeOptions, label } from "@/lib/labels";

describe("labels", () => {
  it("spells out codes that need it", () => {
    expect(label("vpn_server")).toBe("VPN server");
    expect(label("user_activation")).toBe("Activation link");
  });

  it("turns any other code into words", () => {
    expect(label("pending_activation")).toBe("Pending activation");
    expect(label("active")).toBe("Active");
    expect(label("something_new_later")).toBe("Something new later");
  });

  it("keeps the code as the option value", () => {
    expect(codeOptions(["sent"])).toEqual([{ value: "sent", label: "Sent" }]);
  });
});
