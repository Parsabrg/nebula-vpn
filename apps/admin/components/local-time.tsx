"use client";

import { useEffect, useState } from "react";

/** "2026-11-01 06:57 UTC": the same on the server and in any browser. */
export function formatUtc(date: Date): string {
  return `${date.toISOString().slice(0, 16).replace("T", " ")} UTC`;
}

/** The viewer's own clock, short as the design sets it: "14 Nov, 18:02",
 * with the year only when it is not this one. The UTC time is in the
 * title, for anybody who needs the zone. */
export function formatLocal(date: Date, now: Date = new Date()): string {
  return new Intl.DateTimeFormat("en-GB", {
    ...(date.getFullYear() === now.getFullYear()
      ? {}
      : { year: "numeric" as const }),
    month: "short",
    day: "numeric",
    hour: "2-digit",
    minute: "2-digit",
    hourCycle: "h23",
  }).format(date);
}

/**
 * A moment in time, shown in the viewer's zone.
 *
 * The server and the browser's first (hydrating) render both show UTC,
 * which they agree on; once mounted it switches to the browser's zone.
 * Formatting with the browser's zone during render made the server's text
 * and the browser's differ: React error #418 on every page with a time, and
 * some times left in UTC beside others in local time (2026-11-01 sweep).
 */
export function LocalTime({ value }: { value: string | Date }) {
  const [mounted, setMounted] = useState(false);
  useEffect(() => {
    // Deliberate: the one render that must differ from the server's is the
    // one after mounting. useSyncExternalStore kept UTC on a streamed page.
    // eslint-disable-next-line react-hooks/set-state-in-effect
    setMounted(true);
  }, []);
  const date = typeof value === "string" ? new Date(value) : value;
  if (Number.isNaN(date.getTime())) {
    return <span>—</span>;
  }
  return (
    <time dateTime={date.toISOString()} title={formatUtc(date)}>
      {mounted ? formatLocal(date) : formatUtc(date)}
    </time>
  );
}
