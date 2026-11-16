"use client";

import { useState, useTransition } from "react";
import {
  changeAdminRole,
  endAdminSession,
  endAllAdminSessions,
  inviteAdmin,
  loadAdminSessions,
  setAdminDisabled,
} from "@/lib/admins-actions";
import {
  ADMIN_ROLES,
  type AdminItem,
  type AdminRole,
  type AdminSessionItem,
} from "@/lib/admins-shape";
import { CopyButton } from "./copy-button";
import { LocalTime } from "./local-time";
import { MutationButton } from "./mutation-button";

const roleLabel = (role: AdminRole) =>
  ADMIN_ROLES.find((r) => r.value === role)?.label ?? role;

export function AdminsPanel({ initial }: { initial: AdminItem[] }) {
  const [admins, setAdmins] = useState(initial);
  const replace = (next: AdminItem) =>
    setAdmins((all) => all.map((a) => (a.id === next.id ? next : a)));

  // The design's order: the admins in a table, then the form to add one.
  return (
    <>
      <section className="status-card" aria-labelledby="admins-list-title">
        <h2 id="admins-list-title">Admins</h2>
        <table className="data-table" aria-label="Admins">
          <thead>
            <tr>
              <th scope="col">Admin</th>
              <th scope="col">Role</th>
              <th scope="col">Added</th>
              <th scope="col">Actions</th>
            </tr>
          </thead>
          <tbody>
            {admins.map((admin) => (
              <AdminRow key={admin.id} admin={admin} onChange={replace} />
            ))}
          </tbody>
        </table>
      </section>
      <InviteAdmin
        onInvited={(admin) =>
          setAdmins((all) =>
            [...all, admin].sort((a, b) => a.email.localeCompare(b.email)),
          )
        }
      />
    </>
  );
}

function AdminRow({
  admin,
  onChange,
}: {
  admin: AdminItem;
  onChange: (admin: AdminItem) => void;
}) {
  const [role, setRole] = useState<AdminRole>(admin.role);
  const disabled = admin.state === "disabled";

  return (
    <tr>
      <td data-label="Admin">
        <span className="cell-stack">
          <strong>{admin.email}</strong>
          <span className="muted">
            {admin.isYou
              ? "You. Your own password, authenticator and sign-out are on the Security page."
              : admin.username
                ? `Username ${admin.username}`
                : null}
          </span>
          {disabled || !admin.hasAuthenticator ? (
            <span>
              {disabled ? (
                <span className="badge badge--disabled">Disabled</span>
              ) : null}
              {admin.hasAuthenticator ? null : (
                <span className="badge badge--pending_activation">
                  Has not signed in yet
                </span>
              )}
            </span>
          ) : null}
        </span>
      </td>
      <td data-label="Role">{roleLabel(admin.role)}</td>
      <td data-label="Added" className="muted">
        <LocalTime value={admin.createdAt} dateOnly />
        {admin.disabledAt ? (
          <>
            {" · disabled "}
            <LocalTime value={admin.disabledAt} dateOnly />
          </>
        ) : null}
      </td>
      <td data-label="Actions" className="data-table__actions">
        {admin.isYou ? null : (
          <div className="user-actions">
            <MutationButton
              triggerLabel="Change role"
              triggerClassName="button button--small"
              confirmTitle={`Role for ${admin.email}`}
              confirmLabel="Save role"
              confirmBody={
                <>
                  <fieldset className="field">
                    <legend className="field__label">Role</legend>
                    {ADMIN_ROLES.map((option) => (
                      <label key={option.value} className="radio">
                        <input
                          type="radio"
                          name={`role-${admin.id}`}
                          value={option.value}
                          checked={role === option.value}
                          onChange={() => setRole(option.value)}
                        />{" "}
                        <strong>{option.label}</strong>: {option.detail}
                      </label>
                    ))}
                  </fieldset>
                  <p>Their sessions end, so the new role applies at once.</p>
                </>
              }
              action={() => changeAdminRole(admin.id, role)}
              onSuccess={onChange}
            />
            {disabled ? (
              <MutationButton
                triggerLabel="Reactivate"
                triggerClassName="button button--small button--primary"
                confirmTitle={`Reactivate ${admin.email}`}
                confirmLabel="Reactivate"
                confirmBody={
                  <p>They can sign in again with their password and code.</p>
                }
                action={() => setAdminDisabled(admin.id, false)}
                onSuccess={onChange}
              />
            ) : (
              <MutationButton
                triggerLabel="Disable"
                triggerClassName="button button--small button--danger-outline"
                confirmDanger
                confirmTitle={`Disable ${admin.email}`}
                confirmLabel="Disable"
                confirmBody={
                  <p>
                    Every session of theirs ends now and they cannot sign in.
                  </p>
                }
                action={() => setAdminDisabled(admin.id, true)}
                onSuccess={onChange}
              />
            )}
            <AdminSessions adminId={admin.id} />
          </div>
        )}
      </td>
    </tr>
  );
}

function AdminSessions({ adminId }: { adminId: string }) {
  const [sessions, setSessions] = useState<AdminSessionItem[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [pending, start] = useTransition();

  const load = () =>
    start(async () => {
      const result = await loadAdminSessions(adminId);
      if (result.ok) {
        setSessions(result.data);
        setError(null);
      } else {
        setError(result.message);
      }
    });

  if (sessions === null) {
    return (
      <>
        <button
          type="button"
          className="button"
          onClick={load}
          disabled={pending}
        >
          {pending ? "Loading sessions…" : "Sessions"}
        </button>
        {error ? <p role="alert">{error}</p> : null}
      </>
    );
  }

  return (
    <div className="admin-sessions">
      {sessions.length === 0 ? (
        <p>No live sessions.</p>
      ) : (
        <ul>
          {sessions.map((session) => (
            <li key={session.sessionId}>
              Signed in <LocalTime value={session.createdAt} />, last seen{" "}
              <LocalTime value={session.lastSeenAt} />
              {session.mfaMethod === "recovery" ? " (recovery code)" : ""}{" "}
              <MutationButton
                triggerLabel="End"
                triggerClassName="button"
                confirmDanger
                confirmTitle="End this session"
                confirmLabel="End session"
                confirmBody={
                  <p>That browser is signed out at its next request.</p>
                }
                action={() => endAdminSession(adminId, session.sessionId)}
                onSuccess={() =>
                  setSessions((all) =>
                    (all ?? []).filter(
                      (s) => s.sessionId !== session.sessionId,
                    ),
                  )
                }
              />
            </li>
          ))}
        </ul>
      )}
      {sessions.length > 0 ? (
        <MutationButton
          triggerLabel="End all sessions"
          triggerClassName="button"
          confirmDanger
          confirmTitle="End every session"
          confirmLabel="End all"
          confirmBody={<p>They are signed out everywhere.</p>}
          action={() => endAllAdminSessions(adminId)}
          onSuccess={() => setSessions([])}
        />
      ) : null}
    </div>
  );
}

function InviteAdmin({ onInvited }: { onInvited: (admin: AdminItem) => void }) {
  const [email, setEmail] = useState("");
  const [username, setUsername] = useState("");
  const [role, setRole] = useState<AdminRole>("operator");
  const [handout, setHandout] = useState<{
    email: string;
    password: string;
  } | null>(null);

  return (
    <section className="status-card" aria-labelledby="invite-title">
      <h2 id="invite-title">Add an admin</h2>
      <p>
        They get a one-time password from you. At their first sign-in they set
        up an authenticator, then change the password on the Security page.
      </p>
      <MutationButton
        triggerLabel="Add an admin"
        triggerClassName="button button--primary"
        confirmTitle="Add an admin"
        confirmLabel="Add"
        confirmBody={
          <>
            <div className="field">
              <label htmlFor="invite-email" className="field__label">
                Email
              </label>
              <input
                id="invite-email"
                type="email"
                value={email}
                onChange={(event) => setEmail(event.target.value)}
              />
            </div>
            <div className="field">
              <label htmlFor="invite-username" className="field__label">
                Username (optional)
              </label>
              <input
                id="invite-username"
                value={username}
                onChange={(event) => setUsername(event.target.value)}
              />
            </div>
            <div className="field">
              <label htmlFor="invite-role" className="field__label">
                Role
              </label>
              <select
                id="invite-role"
                value={role}
                onChange={(event) => setRole(event.target.value as AdminRole)}
              >
                {ADMIN_ROLES.map((option) => (
                  <option key={option.value} value={option.value}>
                    {option.label}: {option.detail}
                  </option>
                ))}
              </select>
            </div>
          </>
        }
        action={() => inviteAdmin({ email, username, role })}
        onSuccess={({ admin, temporaryPassword }) => {
          onInvited(admin);
          setHandout({ email: admin.email, password: temporaryPassword });
          setEmail("");
          setUsername("");
        }}
      />
      {handout ? (
        <div className="card" role="status">
          <p>
            One-time password for <strong>{handout.email}</strong>. It is shown
            only now; give it to them privately.
          </p>
          <p>
            <code>{handout.password}</code>{" "}
            <CopyButton text={handout.password} />
          </p>
          <button
            type="button"
            className="button"
            onClick={() => setHandout(null)}
          >
            Done
          </button>
        </div>
      ) : null}
    </section>
  );
}
