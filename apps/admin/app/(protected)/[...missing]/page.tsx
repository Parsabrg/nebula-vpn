import { notFound } from "next/navigation";

/** Any other address inside the panel: the not-found page, in the panel's
 * own frame (sidebar and header), as the design draws it. */
export default function Missing() {
  notFound();
}
