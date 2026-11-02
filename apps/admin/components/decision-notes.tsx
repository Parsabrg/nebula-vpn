"use client";

import { createContext, type ReactNode, useContext, useState } from "react";

const Announce = createContext<(note: string) => void>(() => {});

/** For a row to say what its action did; the row itself is gone once the
 * list reloads, so the note is kept here, above the list. */
export function useAnnounce(): (note: string) => void {
  return useContext(Announce);
}

export function DecisionNotes({ children }: { children: ReactNode }) {
  const [notes, setNotes] = useState<string[]>([]);
  return (
    <Announce value={(note) => setNotes((earlier) => [note, ...earlier])}>
      {notes.length > 0 ? (
        <ul role="status" className="decision-notes">
          {notes.map((note, index) => (
            <li key={notes.length - index}>{note}</li>
          ))}
        </ul>
      ) : null}
      {children}
    </Announce>
  );
}
