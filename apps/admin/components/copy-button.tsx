"use client";

import { useState } from "react";

/** Copies [text]; says "Copied" for a moment so the press shows. */
export function CopyButton({
  text,
  label = "Copy",
  primary = false,
}: {
  text: string;
  label?: string;
  /** The page's main action ("Copy link" on Pair a device). */
  primary?: boolean;
}) {
  const [copied, setCopied] = useState(false);
  return (
    <button
      type="button"
      className={primary ? "button button--primary" : "button"}
      onClick={() => {
        void navigator.clipboard.writeText(text).then(() => {
          setCopied(true);
          setTimeout(() => setCopied(false), 2000);
        });
      }}
    >
      <span className="icon" aria-hidden="true">
        content_copy
      </span>
      {copied ? "Copied" : label}
    </button>
  );
}
