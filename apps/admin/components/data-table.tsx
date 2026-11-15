"use client";

import type { ReactNode } from "react";

interface DataTableRow {
  key: string;
  cells: ReactNode[];
}

interface DataTableProps {
  caption: string;
  headers: string[];
  rows: DataTableRow[];
  emptyMessage: string;
  /** Columns holding numbers, set to the right as the design does. */
  numeric?: number[];
}

/**
 * A table; on a narrow screen it scrolls sideways, as the design keeps it,
 * rather than turning into cards.
 */
export function DataTable({
  caption,
  headers,
  rows,
  emptyMessage,
  numeric = [],
}: DataTableProps) {
  if (rows.length === 0) {
    return <p role="status">{emptyMessage}</p>;
  }

  return (
    <table className="data-table" aria-label={caption}>
      <thead>
        <tr>
          {headers.map((header, index) => (
            <th
              scope="col"
              key={header}
              className={numeric.includes(index) ? "num" : undefined}
            >
              {header}
            </th>
          ))}
        </tr>
      </thead>
      <tbody>
        {rows.map((row) => (
          <tr key={row.key}>
            {row.cells.map((cell, index) => (
              <td
                key={headers[index]}
                className={numeric.includes(index) ? "num" : undefined}
              >
                {cell}
              </td>
            ))}
          </tr>
        ))}
      </tbody>
    </table>
  );
}
