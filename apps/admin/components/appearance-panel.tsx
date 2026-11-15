"use client";

import { useState, useSyncExternalStore } from "react";
import {
  ACCENTS,
  LOOKS,
  MODES,
  applyAppearance,
  readAppearance,
  saveAppearance,
  type Appearance,
} from "@/lib/appearance";

/** The swatch beside each accent, as the dark mode draws it. */
const SWATCH: Record<string, string> = {
  blue: "#8ca4ff",
  violet: "#b79cff",
  teal: "#4fd1c5",
  amber: "#e8b24a",
  mono: "#ededf2",
};

function storage(): Storage | undefined {
  try {
    return window.localStorage;
  } catch {
    return undefined;
  }
}

const noSubscribe = () => () => {};

/** Look, Mode and Accent, applied as they are chosen and kept in this browser. */
export function AppearancePanel() {
  // Read once on the client; the server has no say in this browser's choice.
  const stored = useSyncExternalStore(
    noSubscribe,
    () => JSON.stringify(readAppearance(storage())),
    () => null,
  );
  const [choice, setChoice] = useState<Appearance | null>(null);
  const current: Appearance | null =
    choice ?? (stored ? (JSON.parse(stored) as Appearance) : null);

  function change(next: Partial<Appearance>) {
    if (!current) {
      return;
    }
    const value = { ...current, ...next };
    setChoice(value);
    saveAppearance(storage(), value);
    applyAppearance(
      document.documentElement,
      value,
      window.matchMedia("(prefers-color-scheme: dark)").matches,
    );
  }

  if (!current) {
    return null;
  }

  const accentName =
    ACCENTS.find((option) => option.id === current.accent)?.label ?? "";

  return (
    <>
      <section className="status-card" aria-labelledby="look-title">
        <h2 id="look-title">Look</h2>
        <div
          className="look-tiles"
          role="radiogroup"
          aria-labelledby="look-title"
        >
          {LOOKS.map((option) => {
            const on = option.id === current.look;
            return (
              <label
                key={option.id}
                className={`look-tile${on ? " is-selected" : ""}`}
              >
                <input
                  type="radio"
                  name="look"
                  value={option.id}
                  checked={on}
                  onChange={() => change({ look: option.id })}
                  className="visually-hidden"
                  aria-label={option.label}
                />
                <span
                  className={`look-tile__preview look-tile__preview--${option.id}`}
                  aria-hidden="true"
                >
                  <span className="look-tile__bar" />
                  <span className="look-tile__row" />
                  <span className="look-tile__row" />
                </span>
                <span className="look-tile__name">
                  {option.label}
                  {on ? (
                    <span className="icon look-tile__check" aria-hidden="true">
                      check_circle
                    </span>
                  ) : null}
                </span>
                <span className="look-tile__desc">{LOOK_NOTES[option.id]}</span>
              </label>
            );
          })}
        </div>
      </section>

      <section className="status-card" aria-labelledby="mode-title">
        <h2 id="mode-title">Mode</h2>
        <fieldset className="choice-list mode-choices">
          <legend className="visually-hidden">Mode</legend>
          {MODES.map((option) => (
            <label
              key={option.id}
              className={`choice${option.id === current.mode ? " is-selected" : ""}`}
            >
              <input
                type="radio"
                name="mode"
                value={option.id}
                checked={option.id === current.mode}
                onChange={() => change({ mode: option.id })}
              />
              <span>
                <strong>{option.label}</strong>
                {option.id === "system" ? (
                  <span>Follows this computer&apos;s setting</span>
                ) : null}
              </span>
            </label>
          ))}
        </fieldset>
      </section>

      <section className="status-card" aria-labelledby="accent-title">
        <h2 id="accent-title">Accent · {accentName}</h2>
        <div
          className="swatches"
          role="radiogroup"
          aria-labelledby="accent-title"
        >
          {ACCENTS.map((option) => {
            const on = option.id === current.accent;
            return (
              <label
                key={option.id}
                className={`swatch${on ? " is-selected" : ""}`}
                title={option.label}
              >
                <input
                  type="radio"
                  name="accent"
                  value={option.id}
                  checked={on}
                  onChange={() => change({ accent: option.id })}
                  className="visually-hidden"
                  aria-label={option.label}
                />
                <span
                  className="swatch__dot"
                  aria-hidden="true"
                  style={{ background: SWATCH[option.id] }}
                >
                  {on ? <span className="icon">check</span> : null}
                </span>
              </label>
            );
          })}
        </div>
        <p className="status-card__desc">
          The accent marks the main action and what is selected. Green, amber
          and red keep their meanings in every accent.
        </p>
      </section>
    </>
  );
}

/** Each look in a line, as the design describes it. */
const LOOK_NOTES: Record<string, string> = {
  minimal: "Hairlines and mono figures. The densest.",
  glass: "Translucent panels over a soft backdrop.",
  soft: "Solid rounded cards, no borders.",
  expressive: "Tonal colour and big shapes.",
};
