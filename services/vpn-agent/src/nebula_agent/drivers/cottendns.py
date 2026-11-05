"""The DNS tunnel's server (plan 10; ADR 0004, 2026-11-05 revision).

CottenDNS answers one delegated name behind the owner's CottenRouter on port
53, which forwards it to the loopback address here. Fixed-TCP-target mode:
every tunnelled connection goes to this server's VLESS Encryption inbound, so
the tunnel key alone reaches nothing -- a Nebula credential is still needed,
and revocation and allowances apply as on any other route.

The config never changes per user, so it is rendered once at startup and the
unit restarted only when it differs from what is served.
"""

import asyncio
import logging
from pathlib import Path

from nebula_agent.drivers._exec import run_fixed_argv
from nebula_agent.settings import Settings

_LOGGER = logging.getLogger(__name__)
_UNIT = "nebula-cottendns.service"
_SYSTEMCTL_BINARY = "/usr/bin/systemctl"


def _quote(value: str) -> str:
    # TOML basic strings: the values here are names, addresses and paths.
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def render_cottendns_config(settings: Settings) -> str | None:
    """The server's config, or None when this server runs no DNS tunnel."""

    if not settings.cottendns_domains:
        return None
    host, _, port = settings.cottendns_listen.rpartition(":")
    return "\n".join(
        [
            "# Rendered by nebula-agent; edits are overwritten at its next start.",
            "DOMAIN = ["
            + ", ".join(_quote(name) for name in settings.cottendns_domains.split(","))
            + "]",
            # One fixed target: this server's VLESS Encryption inbound.
            'PROTOCOL_TYPE = "TCP"',
            'FORWARD_IP = "127.0.0.1"',
            f"FORWARD_PORT = {settings.xray_vlessenc_port}",
            # Behind CottenRouter, which owns port 53.
            f"UDP_HOST = {_quote(host)}",
            f"UDP_PORT = {port}",
            "TCP_LISTENER_ENABLED = true",
            # AES-256-GCM only: no other method is tried.
            "DATA_ENCRYPTION_METHOD = 5",
            "ENCRYPTION_AUTO_DETECT = false",
            f"ENCRYPTION_KEY_FILE = {_quote(str(settings.cottendns_key_file))}",
            'LOG_LEVEL = "WARN"',
            "",
        ]
    )


def _write_if_changed(path: Path, rendered: str) -> bool:
    try:
        if path.read_text(encoding="utf-8") == rendered:
            return False
    except FileNotFoundError:
        pass
    temporary = path.with_suffix(".tmp")
    temporary.write_text(rendered, encoding="utf-8")
    # Group-readable: CottenDNS runs as its own user, in the folder's group.
    temporary.chmod(0o640)
    temporary.replace(path)
    return True


async def apply_cottendns(settings: Settings) -> bool:
    """Write the config and restart the server when it changed. True if so."""

    rendered = render_cottendns_config(settings)
    if rendered is None:
        return False
    path = Path(str(settings.cottendns_config_file))
    if not await asyncio.to_thread(_write_if_changed, path, rendered):
        return False
    result = await run_fixed_argv([_SYSTEMCTL_BINARY, "restart", _UNIT], timeout_seconds=30)
    if result.returncode != 0:
        _LOGGER.warning("restarting %s failed: %s", _UNIT, result.stderr.decode(errors="replace"))
    return True
