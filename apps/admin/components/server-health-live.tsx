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

/** A table cell's badge for one of a server's live checks: OK, Down or
 * Unknown, "…" until the answer is in. */
export function ServerLiveBadge({
  serverId,
  check,
}: {
  serverId: string;
  check: "agent" | "xray" | "wireguard";
}) {
  const { live, wireguard, xray } = useServer(serverId);
  if (live.status === "checking") return <span className="muted">…</span>;
  // Said plainly, not "Unknown": the check itself did not get through.
  if (live.status === "failed") {
    return <span className="muted">Could not check</span>;
  }
  const up: boolean | null | undefined =
    check === "agent"
      ? wireguard === undefined
        ? null
        : wireguard.state === "healthy"
      : check === "xray"
        ? xray === undefined
          ? undefined
          : xray.listenerUp
        : (wireguard?.interfaceUp ?? null);
  if (up === undefined) return <span className="muted">Not enabled</span>;
  const [tone, word] =
    up === null
      ? ["unknown", "Unknown"]
      : up
        ? ["active", "OK"]
        : ["failed", "Down"];
  const detail =
    check === "xray" && xray?.errorCode
      ? xray.errorCode
      : check === "agent"
        ? (wireguard?.agentVersion ?? undefined)
        : check === "wireguard" && wireguard?.peerCount != null
          ? `${wireguard.peerCount} peers`
          : undefined;
  return (
    <span className={`badge badge--${tone}`} title={detail}>
      {word}
    </span>
  );
}

/** When the server last answered, for a table cell. */
export function ServerCheckedText({ serverId }: { serverId: string }) {
  const { live, wireguard } = useServer(serverId);
  if (live.status !== "ready") return <span className="muted">…</span>;
  if (!wireguard) return <span className="muted">never</span>;
  const at = wireguard.observedAt;
  const seconds = Math.max(0, (live.at - new Date(at).getTime()) / 1000);
  return (
    <time className="muted" dateTime={at} title={new Date(at).toISOString()}>
      {seconds < 90
        ? "just now"
        : seconds < 5400
          ? `${Math.round(seconds / 60)} min ago`
          : seconds < 172800
            ? `${Math.round(seconds / 3600)} h ago`
            : `${Math.round(seconds / 86400)} days ago`}
    </time>
  );
}
