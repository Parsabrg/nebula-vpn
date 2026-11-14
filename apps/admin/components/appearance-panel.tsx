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

  return (
    <section className="status-card" aria-label="Appearance">
      <Choices
        legend="Look"
        name="look"
        options={LOOKS}
        value={current.look}
        onChange={(look) => change({ look })}
      />
      <Choices
        legend="Mode"
        name="mode"
        options={MODES}
        value={current.mode}
        onChange={(mode) => change({ mode })}
      />
      <Choices
        legend="Accent"
        name="accent"
        options={ACCENTS}
        value={current.accent}
        onChange={(accent) => change({ accent })}
        swatch
      />
    </section>
  );
}

function Choices<T extends string>({
  legend,
  name,
  options,
  value,
  onChange,
  swatch = false,
}: {
  legend: string;
  name: string;
  options: readonly { id: T; label: string }[];
  value: T;
  onChange: (value: T) => void;
  swatch?: boolean;
}) {
  return (
    <fieldset className="appearance-choices">
      <legend>{legend}</legend>
      <div className="appearance-options">
        {options.map((option) => (
          <label className="appearance-option" key={option.id}>
            <input
              type="radio"
              name={name}
              value={option.id}
              checked={option.id === value}
              onChange={() => onChange(option.id)}
            />
            {swatch ? (
              <span
                className="appearance-swatch"
                aria-hidden="true"
                style={{ background: SWATCH[option.id] }}
              />
            ) : null}
            {option.label}
          </label>
        ))}
      </div>
    </fieldset>
  );
}
