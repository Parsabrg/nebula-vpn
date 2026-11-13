"use client";

import { useRouter } from "next/navigation";
import { useState } from "react";
import type { LinkOption } from "@/lib/subscription-link";
import { setSubscriptionLink } from "@/lib/subscription-link-actions";
import { MutationButton } from "./mutation-button";

/** Pick the address new subscription links name. */
export function SubscriptionLinkControl({
  choice,
  options,
}: {
  choice: string;
  options: LinkOption[];
}) {
  const router = useRouter();
  const [draft, setDraft] = useState(choice);
  const label =
    options.find((option) => option.value === draft)?.label ?? draft;

  return (
    <div className="auth-form">
      <fieldset className="field">
        <legend className="field__label">Address in new links</legend>
        {options.map((option) => (
          <label key={option.value} className="relay-port">
            <input
              type="radio"
              name="subscription-link"
              value={option.value}
              checked={draft === option.value}
              onChange={() => setDraft(option.value)}
            />
            <span>{option.label}</span>
          </label>
        ))}
      </fieldset>
      {draft === choice ? (
        <button type="button" className="button button--primary" disabled>
          Save
        </button>
      ) : (
        <MutationButton
          triggerLabel="Save"
          triggerClassName="button button--primary"
          confirmTitle="Change the address in subscription links"
          confirmLabel="Save"
          confirmBody={
            <p>
              New links will name: {label}. Links made before keep the address
              they were made with; people make a new one in the app to move.
            </p>
          }
          action={() => setSubscriptionLink(draft)}
          onSuccess={() => router.refresh()}
        />
      )}
    </div>
  );
}
