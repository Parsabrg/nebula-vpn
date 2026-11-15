"use client";

import { useEffect, useRef, useState, type ReactNode } from "react";
import { createPortal } from "react-dom";

interface ConfirmDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  title: string;
  confirmLabel: string;
  pending: boolean;
  error: string | null;
  onConfirm: () => void;
  children?: ReactNode;
  /** Removing or refusing: the confirm button is red, not blue. */
  danger?: boolean;
}

/**
 * Wraps a native <dialog> as a controlled component: React owns `open`,
 * an effect drives showModal()/close(), and the dialog's own `cancel`/`close`
 * events (fired on Escape, among other things) sync back into `open`.
 */
export function ConfirmDialog({
  open,
  onOpenChange,
  title,
  confirmLabel,
  pending,
  error,
  onConfirm,
  children,
  danger = false,
}: ConfirmDialogProps) {
  const dialogRef = useRef<HTMLDialogElement>(null);
  // Rendered into <body>, not where it is written: a dialog opened from
  // inside another one's form (Manage, then "Give every user this server")
  // put a form inside a form, which HTML forbids and React's hydration
  // failed on. The top layer is where a modal dialog is drawn anyway.
  const [mounted, setMounted] = useState(false);
  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect -- the portal needs the document, which only exists after mounting
    setMounted(true);
  }, []);

  useEffect(() => {
    const dialog = dialogRef.current;
    if (!dialog) {
      return;
    }
    if (open && !dialog.open) {
      dialog.showModal();
    } else if (!open && dialog.open) {
      dialog.close();
    }
  }, [open, mounted]);

  if (!mounted) {
    return null;
  }
  return createPortal(
    <dialog
      ref={dialogRef}
      className="dialog"
      onClose={() => {
        onOpenChange(false);
      }}
      onCancel={() => {
        onOpenChange(false);
      }}
    >
      <form
        className="dialog__form"
        onSubmit={(event) => {
          event.preventDefault();
          onConfirm();
        }}
      >
        <h2>{title}</h2>
        {children}
        {error ? (
          <p role="alert" className="field__error">
            {error}
          </p>
        ) : null}
        <div className="dialog__actions">
          <button
            type="button"
            className="button button--ghost"
            disabled={pending}
            onClick={() => {
              onOpenChange(false);
            }}
          >
            Cancel
          </button>
          <button
            type="submit"
            className={
              danger ? "button button--danger" : "button button--primary"
            }
            disabled={pending}
          >
            {pending ? "Working…" : confirmLabel}
          </button>
        </div>
      </form>
    </dialog>,
    document.body,
  );
}
