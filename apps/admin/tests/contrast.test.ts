import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

/**
 * WCAG AA (4.5:1) for text in every look x mode x accent, read from the
 * tokens in globals.css itself so the test and the panel cannot disagree.
 */
const css = readFileSync(join(__dirname, "../app/globals.css"), "utf8");

function block(selector: string): Record<string, string> {
  const start = css.indexOf(`${selector} {`);
  if (start < 0) {
    throw new Error(`no block for ${selector}`);
  }
  const body = css.slice(start, css.indexOf("}", start));
  const vars: Record<string, string> = {};
  for (const match of body.matchAll(/--([\w-]+):\s*([^;]+);/g)) {
    vars[match[1]] = match[2].trim();
  }
  return vars;
}

type Rgba = [number, number, number, number];

function parse(colour: string): Rgba {
  const hex = /^#([0-9a-f]{6})$/i.exec(colour);
  if (hex) {
    const n = parseInt(hex[1], 16);
    return [(n >> 16) & 255, (n >> 8) & 255, n & 255, 1];
  }
  const rgba = /^rgba?\(([^)]+)\)$/.exec(colour);
  if (rgba) {
    const [r, g, b, a = "1"] = rgba[1].split(",").map((s) => s.trim());
    return [Number(r), Number(g), Number(b), Number(a)];
  }
  throw new Error(`cannot read ${colour}`);
}

function over(top: Rgba, under: Rgba): Rgba {
  const a = top[3];
  return [
    top[0] * a + under[0] * (1 - a),
    top[1] * a + under[1] * (1 - a),
    top[2] * a + under[2] * (1 - a),
    1,
  ];
}

function luminance([r, g, b]: Rgba): number {
  const lin = (c: number) => {
    const s = c / 255;
    return s <= 0.03928 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4;
  };
  return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b);
}

function ratio(a: Rgba, b: Rgba): number {
  const [hi, lo] = [luminance(a), luminance(b)].sort((x, y) => y - x);
  return (hi + 0.05) / (lo + 0.05);
}

const LOOKS = ["minimal", "glass", "soft", "expressive"];
const MODES = ["dark", "light"];
const ACCENTS = ["blue", "violet", "teal", "amber", "mono"];

describe("admin contrast", () => {
  const failures: string[] = [];
  for (const look of LOOKS) {
    for (const mode of MODES) {
      const t = block(`:root[data-look="${look}"][data-theme="${mode}"]`);
      const bg = parse(t.background);
      const grounds: Record<string, Rgba> = {
        background: bg,
        surface: over(parse(t.surface), bg),
        raised: over(parse(t["surface-raised"]), bg),
        side: over(parse(t.side), bg),
      };
      for (const accent of ACCENTS) {
        const a = block(
          accent === "blue"
            ? `:root[data-theme="${mode}"][data-accent="blue"]`
            : `:root[data-theme="${mode}"][data-accent="${accent}"]`,
        );
        const inks: Record<string, Rgba> = {
          text: parse(t.text),
          muted: parse(t.muted),
          accent: parse(a["accent-text"]),
          danger: parse(t["danger-text"]),
          warning: parse(t["warning-text"]),
          ok: parse(t.ok),
        };
        for (const [groundName, ground] of Object.entries(grounds)) {
          for (const [inkName, ink] of Object.entries(inks)) {
            const r = ratio(over(ink, ground), ground);
            if (r < 4.5) {
              failures.push(
                `${look} ${mode} ${accent}: ${inkName} on ${groundName} ${r.toFixed(2)}`,
              );
            }
          }
        }
        const onAccent = ratio(parse(a["accent-ink"]), parse(a.accent));
        if (onAccent < 4.5) {
          failures.push(`${look} ${mode} ${accent}: ink on accent ${onAccent}`);
        }
      }
      const onDanger = ratio(parse(t["on-danger"]), parse(t.danger));
      if (onDanger < 4.5) {
        failures.push(`${look} ${mode}: on-danger ${onDanger.toFixed(2)}`);
      }
    }
  }

  it("every text colour reads at 4.5:1 or more", () => {
    expect(failures).toEqual([]);
  });
});
