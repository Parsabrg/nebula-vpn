import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { beforeEach, describe, expect, it } from "vitest";
import { AppearancePanel } from "@/components/appearance-panel";
import {
  APPEARANCE_KEY,
  DEFAULT_APPEARANCE,
  applyAppearance,
  readAppearance,
} from "@/lib/appearance";

describe("appearance", () => {
  beforeEach(() => {
    window.localStorage.clear();
    delete document.documentElement.dataset.look;
    delete document.documentElement.dataset.accent;
    delete document.documentElement.dataset.theme;
  });

  it("falls back to the defaults for missing or unknown values", () => {
    expect(readAppearance(window.localStorage)).toEqual(DEFAULT_APPEARANCE);
    window.localStorage.setItem(
      APPEARANCE_KEY,
      JSON.stringify({ look: "neon", mode: "dark", accent: "teal" }),
    );
    expect(readAppearance(window.localStorage)).toEqual({
      look: "minimal",
      mode: "dark",
      accent: "teal",
    });
    window.localStorage.setItem(APPEARANCE_KEY, "{not json");
    expect(readAppearance(window.localStorage)).toEqual(DEFAULT_APPEARANCE);
  });

  it("resolves System to the system's mode", () => {
    const root = document.documentElement;
    applyAppearance(root, { ...DEFAULT_APPEARANCE, mode: "system" }, false);
    expect(root.dataset.theme).toBe("light");
    applyAppearance(root, { ...DEFAULT_APPEARANCE, mode: "system" }, true);
    expect(root.dataset.theme).toBe("dark");
    applyAppearance(root, { ...DEFAULT_APPEARANCE, mode: "light" }, true);
    expect(root.dataset.theme).toBe("light");
  });

  it("applies and keeps a choice in this browser", async () => {
    render(<AppearancePanel />);

    await userEvent.click(screen.getByRole("radio", { name: "Liquid glass" }));
    await userEvent.click(screen.getByRole("radio", { name: "Violet" }));

    expect(document.documentElement.dataset.look).toBe("glass");
    expect(document.documentElement.dataset.accent).toBe("violet");
    expect(readAppearance(window.localStorage)).toMatchObject({
      look: "glass",
      accent: "violet",
    });
    expect(screen.getByRole("radio", { name: "Liquid glass" })).toBeChecked();
  });
});
