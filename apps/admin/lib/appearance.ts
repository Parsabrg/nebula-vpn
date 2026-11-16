/**
 * How the panel looks in this browser: a look, a mode and an accent, kept in
 * localStorage (DESIGN_SPEC section 5, Appearance). It changes nothing in the
 * app and nothing other admins see.
 *
 * Applied as attributes on <html>, which globals.css keys its tokens on:
 * data-look, data-accent, and data-theme (the mode resolved to dark or light).
 */

export const LOOKS = [
  { id: "minimal", label: "Minimal" },
  { id: "glass", label: "Liquid glass" },
  { id: "soft", label: "Soft cards" },
  { id: "expressive", label: "Expressive" },
] as const;

export const MODES = [
  { id: "light", label: "Light" },
  { id: "dark", label: "Dark" },
  { id: "system", label: "System" },
] as const;

export const ACCENTS = [
  { id: "blue", label: "Blue" },
  { id: "violet", label: "Violet" },
  { id: "teal", label: "Teal" },
  { id: "amber", label: "Amber" },
  { id: "mono", label: "Mono" },
] as const;

export type Look = (typeof LOOKS)[number]["id"];
export type Mode = (typeof MODES)[number]["id"];
export type Accent = (typeof ACCENTS)[number]["id"];

export interface Appearance {
  look: Look;
  mode: Mode;
  accent: Accent;
}

export const DEFAULT_APPEARANCE: Appearance = {
  look: "minimal",
  mode: "system",
  accent: "blue",
};

export const APPEARANCE_KEY = "nebula.admin.appearance";

function oneOf<T extends string>(
  value: unknown,
  options: readonly { id: T }[],
  fallback: T,
): T {
  return options.some((o) => o.id === value) ? (value as T) : fallback;
}

/** What this browser keeps; the defaults for anything missing or unknown. */
export function readAppearance(storage: Storage | undefined): Appearance {
  let raw: Partial<Appearance> = {};
  try {
    raw = JSON.parse(storage?.getItem(APPEARANCE_KEY) ?? "{}") ?? {};
  } catch {
    // Unreadable (private window, blocked storage, a bad value): defaults.
  }
  return {
    look: oneOf(raw.look, LOOKS, DEFAULT_APPEARANCE.look),
    mode: oneOf(raw.mode, MODES, DEFAULT_APPEARANCE.mode),
    accent: oneOf(raw.accent, ACCENTS, DEFAULT_APPEARANCE.accent),
  };
}

export function saveAppearance(
  storage: Storage | undefined,
  appearance: Appearance,
): void {
  try {
    storage?.setItem(APPEARANCE_KEY, JSON.stringify(appearance));
  } catch {
    // Not kept, but still applied to this page.
  }
}

/** Sets the attributes the tokens key on. */
export function applyAppearance(
  root: HTMLElement,
  appearance: Appearance,
  systemDark: boolean,
): void {
  const dark =
    appearance.mode === "system" ? systemDark : appearance.mode === "dark";
  root.dataset.look = appearance.look;
  root.dataset.accent = appearance.accent;
  root.dataset.theme = dark ? "dark" : "light";
}

/**
 * The same, inline in <head> before anything paints, so a light or glass
 * panel does not flash dark first. Kept tiny and dependency-free; it follows
 * the system's mode while the page is open.
 */
export const APPEARANCE_BOOT_SCRIPT = `(function(){try{
var k=${JSON.stringify(APPEARANCE_KEY)},L=${JSON.stringify(LOOKS.map((l) => l.id))},M=${JSON.stringify(MODES.map((m) => m.id))},A=${JSON.stringify(ACCENTS.map((a) => a.id))};
var r=document.documentElement,a={};try{a=JSON.parse(localStorage.getItem(k)||"{}")||{}}catch(e){}
var look=L.indexOf(a.look)>=0?a.look:"minimal",mode=M.indexOf(a.mode)>=0?a.mode:"system",acc=A.indexOf(a.accent)>=0?a.accent:"blue";
var q=window.matchMedia("(prefers-color-scheme: dark)");
function set(){var d=mode==="system"?q.matches:mode==="dark";r.dataset.look=look;r.dataset.accent=acc;r.dataset.theme=d?"dark":"light"}
set();if(mode==="system"&&q.addEventListener)q.addEventListener("change",set);
}catch(e){}})();`;
