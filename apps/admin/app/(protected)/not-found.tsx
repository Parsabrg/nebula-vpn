import type { Metadata } from "next";
import Link from "next/link";

export const metadata: Metadata = {
  title: "Not found",
};

/** A wrong address inside the panel, with the sidebar still there. */
export default function NotFound() {
  return (
    <section
      className="page-heading page-heading--actions"
      aria-labelledby="not-found-title"
    >
      <div>
        <h1 id="not-found-title">Page not found</h1>
        <p>That page does not exist in the admin panel.</p>
      </div>
      <div className="page-heading__actions">
        <Link className="button button--primary" href="/">
          Go to Overview
        </Link>
      </div>
    </section>
  );
}
