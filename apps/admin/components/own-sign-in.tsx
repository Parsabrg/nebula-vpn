"use client";

import { type FormEvent, useRef, useState } from "react";
import { readCsrfCookie } from "@/lib/csrf-client";
import { RecoveryCodeActions } from "./login-flow";
import { StepUpModal } from "./step-up-modal";

type Sent<T> = { ok: true; body: T } | { ok: false; message: string };

/**
 * Posts to one of the panel's auth routes. A request without a fresh code
 * comes back 403 step_up_required: then the code dialog opens, and the same
 * request is sent again once the code is accepted.
 */
function useSteppedUpPost() {
  const [asking, setAsking] = useState(false);
  const retry = useRef<(() => void) | null>(null);

  async function post<T>(path: string, body: unknown): Promise<Sent<T> | null> {
    const headers: HeadersInit = { "Content-Type": "application/json" };
    const csrf = readCsrfCookie();
    if (csrf) headers["X-CSRF-Token"] = csrf;
    const response = await fetch(path, {
      method: "POST",
      headers,
      body: JSON.stringify(body),
    });
    const payload = (await response.json().catch(() => ({}))) as {
      detail?: unknown;
    };
    if (response.ok) return { ok: true, body: payload as T };
    if (response.status === 403 && payload.detail === "step_up_required") {
      return null;
    }
    return {
      ok: false,
      message:
        response.status === 409 && typeof payload.detail === "string"
          ? payload.detail
          : response.status === 429
            ? "Too many tries. Wait a few minutes, then try again."
            : "That did not work. Try again.",
    };
  }

  /** Runs [attempt]; if it needs a code, asks for one and runs it again. */
  function run(attempt: () => Promise<boolean>) {
    void attempt().then((done) => {
      if (!done) {
        retry.current = () => void attempt();
        setAsking(true);
      }
    });
  }

  const modal = (
    <StepUpModal
      open={asking}
      onCancel={() => setAsking(false)}
      onVerified={() => {
        setAsking(false);
        retry.current?.();
      }}
    />
  );
  return { post, run, modal };
}

export function ChangeOwnPassword() {
  const { post, run, modal } = useSteppedUpPost();
  const [current, setCurrent] = useState("");
  const [next, setNext] = useState("");
  const [repeat, setRepeat] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [done, setDone] = useState(false);
  const [pending, setPending] = useState(false);

  function submit(event: FormEvent) {
    event.preventDefault();
    setError(null);
    if (next !== repeat) {
      setError("The new password and its repeat are not the same.");
      return;
    }
    run(async () => {
      setPending(true);
      try {
        const sent = await post("/api/admin/auth/password", {
          current_password: current,
          new_password: next,
        });
        if (sent === null) return false;
        if (sent.ok) {
          setDone(true);
          setCurrent("");
          setNext("");
          setRepeat("");
        } else {
          setError(sent.message);
        }
        return true;
      } finally {
        setPending(false);
      }
    });
  }

  if (done) {
    return (
      <p role="status">
        Password changed. Every other session of yours is signed out; this one
        stays signed in.
      </p>
    );
  }
  // The code dialog has a form of its own, so it sits beside this one:
  // nested, the browser submitted the outer form with the code in the URL.
  return (
    <>
      <form className="auth-form" onSubmit={submit}>
        <div className="field">
          <label htmlFor="own-current" className="field__label">
            Current password
          </label>
          <input
            id="own-current"
            type="password"
            autoComplete="current-password"
            value={current}
            onChange={(event) => setCurrent(event.target.value)}
            required
          />
        </div>
        <div className="field">
          <label htmlFor="own-new" className="field__label">
            New password
          </label>
          <input
            id="own-new"
            type="password"
            autoComplete="new-password"
            value={next}
            onChange={(event) => setNext(event.target.value)}
            required
          />
        </div>
        <div className="field">
          <label htmlFor="own-repeat" className="field__label">
            New password again
          </label>
          <input
            id="own-repeat"
            type="password"
            autoComplete="new-password"
            value={repeat}
            onChange={(event) => setRepeat(event.target.value)}
            required
          />
        </div>
        {error ? (
          <p role="alert" className="field__error">
            {error}
          </p>
        ) : null}
        <button
          type="submit"
          className="button button--primary"
          disabled={pending}
        >
          {pending ? "Changing…" : "Change password"}
        </button>
      </form>
      {modal}
    </>
  );
}

interface Setup {
  secret: string;
  provisioning_uri: string;
  qr_svg: string;
}

export function ReplaceOwnAuthenticator() {
  const { post, run, modal } = useSteppedUpPost();
  const [setup, setSetup] = useState<Setup | null>(null);
  const [code, setCode] = useState("");
  const [codes, setCodes] = useState<string[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [pending, setPending] = useState(false);

  function start() {
    setError(null);
    run(async () => {
      setPending(true);
      try {
        const sent = await post<Setup>("/api/admin/auth/mfa/replace", {});
        if (sent === null) return false;
        if (sent.ok) setSetup(sent.body);
        else setError(sent.message);
        return true;
      } finally {
        setPending(false);
      }
    });
  }

  function confirm(event: FormEvent) {
    event.preventDefault();
    setError(null);
    run(async () => {
      setPending(true);
      try {
        const sent = await post<{ recovery_codes: string[] }>(
          "/api/admin/auth/mfa/replace/confirm",
          { code: code.trim() },
        );
        if (sent === null) return false;
        if (sent.ok) setCodes(sent.body.recovery_codes);
        else setError(sent.message);
        return true;
      } finally {
        setPending(false);
      }
    });
  }

  if (codes) {
    return (
      <div>
        <p role="status">
          The new authenticator is in use; the old one and your old recovery
          codes no longer work. Save these new codes now; they will not be shown
          again.
        </p>
        <ol className="recovery-codes" aria-label="Recovery codes">
          {codes.map((item) => (
            <li key={item}>{item}</li>
          ))}
        </ol>
        <RecoveryCodeActions codes={codes} />
      </div>
    );
  }
  if (setup) {
    return (
      <>
        <form className="auth-form" onSubmit={confirm}>
          <p>
            Scan this code with the new authenticator app, or type the key into
            it. Your current authenticator keeps working until you confirm.
          </p>
          {/* eslint-disable-next-line @next/next/no-img-element -- an inline data URL, nothing to optimise */}
          <img
            src={`data:image/svg+xml;charset=utf-8,${encodeURIComponent(setup.qr_svg)}`}
            alt="QR code for the new authenticator app"
            width={200}
            height={200}
          />
          <p className="mfa-secret" aria-label="New setup key">
            {setup.secret}
          </p>
          <div className="field">
            <label htmlFor="own-new-code" className="field__label">
              Code from the new authenticator
            </label>
            <input
              id="own-new-code"
              inputMode="numeric"
              autoComplete="one-time-code"
              value={code}
              onChange={(event) => setCode(event.target.value)}
              required
            />
          </div>
          {error ? (
            <p role="alert" className="field__error">
              {error}
            </p>
          ) : null}
          <button
            type="submit"
            className="button button--primary"
            disabled={pending}
          >
            {pending ? "Checking…" : "Use the new authenticator"}
          </button>
        </form>
        {modal}
      </>
    );
  }
  return (
    <div>
      <p>
        Moving to a new phone or app? Set up the new one here; the current one
        keeps working until the new one gives a right code.
      </p>
      {error ? (
        <p role="alert" className="field__error">
          {error}
        </p>
      ) : null}
      <button
        type="button"
        className="button"
        disabled={pending}
        onClick={start}
      >
        {pending ? "Starting…" : "Set up a new authenticator"}
      </button>
      {modal}
    </div>
  );
}
