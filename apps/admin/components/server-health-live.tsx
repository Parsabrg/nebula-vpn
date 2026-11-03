"use client";

import {
  createContext,
  type ReactNode,
  useCallback,
  useContext,
  useEffect,
  useState,
} from "react";
import {
  type LiveServerHealth,
  loadServerHealth,
} from "@/lib/topology-actions";

type Live =
  | { status: "checking" }
  | { status: "failed" }
  | { status: "ready"; data: LiveServerHealth; at: number };

const LiveContext = createContext<Live>({ status: "checking" });

/** How often the live checks are asked for again while the page is open. */
const REFRESH_MS = 30_000;

/**
 * The servers' own answers, fetched after the page is on screen.
 *
 * Asking every agent takes as long as the slowest one, and an agent across a
 * slow international link once took six seconds (2026-11-03): with the page
 * waiting for it, clicks elsewhere seemed to do nothing. The page shows at
 * once; these fill in when they arrive, and again every 30 seconds.
 */
export function ServerHealthLive({ children }: { children: ReactNode }) {
  const [live, setLive] = useState<Live>({ status: "checking" });
  const refresh = useCallback(async () => {
    try {
      const result = await loadServerHealth();
      setLive(
        result.ok
          ? { status: "ready", data: result.data, at: Date.now() }
          : { status: "failed" },
      );
    } catch {
      setLive({ status: "failed" });
    }
  }, []);
  useEffect(() => {
    // Fetching on mount is the point: the page is already on screen.
    // eslint-disable-next-line react-hooks/set-state-in-effect
    void refresh();
    const timer = setInterval(() => void refresh(), REFRESH_MS);
    return () => clearInterval(timer);
  }, [refresh]);
  return <LiveContext value={live}>{children}</LiveContext>;
}

function useServer(serverId: string) {
  const live = useContext(LiveContext);
  if (live.status !== "ready")
    return { live, wireguard: undefined, xray: undefined };
  return {
    live,
    wireguard: live.data.health.find((item) => item.serverId === serverId),
    xray: live.data.xray.find((item) => item.serverId === serverId),
  };
}

/** "Healthy · 52 ms", or what is wrong; "Checking…" until the answer is in. */
export function ServerVerdict({ serverId }: { serverId: string }) {
  const { live, wireguard, xray } = useServer(serverId);
  if (live.status === "checking") {
    return <p className="server-card__verdict is-checking">Checking…</p>;
  }
  if (live.status === "failed") {
    return (
      <p className="server-card__verdict is-bad">Could not check right now</p>
    );
  }
  const healthy =
    wireguard?.state === "healthy" &&
    (xray === undefined || xray.listenerUp === true);
  const verdict =
    wireguard === undefined
      ? "Not checked yet"
      : healthy
        ? "Healthy"
        : wireguard.state !== "healthy"
          ? `Agent ${wireguard.state}`
          : xray?.listenerUp === null
            ? "Xray not checked"
            : "Xray listener down";
  return (
    <p className={`server-card__verdict ${healthy ? "is-ok" : "is-bad"}`}>
      {verdict}
      {wireguard?.latencyMs != null ? ` · ${wireguard.latencyMs} ms` : ""}
    </p>
  );
}

/** Xray, WireGuard and agent version rows of a server card. */
export function ServerLiveFacts({ serverId }: { serverId: string }) {
  const { live, wireguard, xray } = useServer(serverId);
  const pending = live.status !== "ready";
  return (
    <>
      <dt>Xray</dt>
      <dd>
        {pending
          ? "…"
          : xray === undefined
            ? "not enabled"
            : xray.listenerUp === null
              ? `unknown${xray.errorCode ? ` (${xray.errorCode})` : ""}`
              : xray.listenerUp
                ? "up"
                : `down${xray.errorCode ? ` (${xray.errorCode})` : ""}`}
      </dd>
      <dt>WireGuard</dt>
      <dd>
        {pending
          ? "…"
          : wireguard?.interfaceUp == null
            ? "unknown"
            : wireguard.interfaceUp
              ? `up · ${wireguard.peerCount ?? 0} peers`
              : "down"}
      </dd>
      <dt>Agent</dt>
      <dd>{pending ? "…" : (wireguard?.agentVersion ?? "unknown")}</dd>
    </>
  );
}

/** "Checked" row: when the server last answered, the exact time on hover. */
export function ServerChecked({ serverId }: { serverId: string }) {
  const { live, wireguard } = useServer(serverId);
  if (live.status !== "ready") return <dd>…</dd>;
  if (!wireguard) return <dd>never</dd>;
  const at = wireguard.observedAt;
  const seconds = Math.max(0, (live.at - new Date(at).getTime()) / 1000);
  return (
    <dd>
      <time dateTime={at} title={new Date(at).toISOString()}>
        {seconds < 90 ? "just now" : `${Math.round(seconds / 60)} min ago`}
      </time>
    </dd>
  );
}

/** The reconciliation summary, which needs to know whether any agent is
 * unreachable before it can say "All in sync". */
export function ReconciliationSummary({
  outstanding,
}: {
  outstanding: number;
}) {
  const live = useContext(LiveContext);
  if (outstanding > 0) {
    return (
      <>
        {outstanding} record{outstanding === 1 ? " is" : "s are"} waiting or
        need review.
      </>
    );
  }
  if (live.status !== "ready") return <>Checking the servers…</>;
  const unchecked = live.data.health.filter(
    (item) => item.state === "unreachable",
  ).length;
  return unchecked > 0 ? (
    <>
      Not checked:{" "}
      {unchecked === 1
        ? "one server's agent is"
        : `${unchecked} servers' agents are`}{" "}
      unreachable.
    </>
  ) : (
    <>All in sync: every credential is where it should be.</>
  );
}
