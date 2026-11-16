import Link from "next/link";

type StatTileProps = Readonly<{
  label: string;
  value: number;
  href: string;
  /** A line under the label in the warning colour ("Waiting for a
   * decision"). */
  note?: string | undefined;
}>;

export function StatTile({ label, value, href, note }: StatTileProps) {
  return (
    <Link className="stat-tile" href={href}>
      <span className="stat-tile__value">{value}</span>
      <span className="stat-tile__label">{label}</span>
      {note ? <span className="stat-tile__note">{note}</span> : null}
    </Link>
  );
}
