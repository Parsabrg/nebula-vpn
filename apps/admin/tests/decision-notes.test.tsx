import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { useState } from "react";
import { describe, expect, it } from "vitest";
import { DecisionNotes, useAnnounce } from "@/components/decision-notes";

function Row() {
  const announce = useAnnounce();
  const [gone, setGone] = useState(false);
  if (gone) return null;
  return (
    <button
      type="button"
      onClick={() => {
        announce("Approved a@x.test: activation email sent.");
        setGone(true);
      }}
    >
      Approve
    </button>
  );
}

describe("DecisionNotes", () => {
  it("keeps what a row did after the row is gone", async () => {
    const user = userEvent.setup();
    render(
      <DecisionNotes>
        <Row />
      </DecisionNotes>,
    );

    await user.click(screen.getByRole("button", { name: "Approve" }));

    expect(screen.queryByRole("button")).toBeNull();
    expect(screen.getByRole("status")).toHaveTextContent(
      "Approved a@x.test: activation email sent.",
    );
  });
});
