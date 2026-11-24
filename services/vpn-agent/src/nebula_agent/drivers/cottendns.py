"""The DNS tunnel's server.

CottenDNS answers the names delegated to this server and forwards every
tunnelled connection to this server's VLESS Encryption inbound (fixed-TCP-
target mode), so the tunnel key alone reaches nothing -- a Nebula credential
is still needed, and revocation and allowances apply as on any other route.

The control plane says which names and key (api/v1_dns_tunnel.py), as
desired state; where it listens is this server's own (cottendns_listen, set
by install.sh: port 53 when the server has it free, else loopback behind
whatever owns 53). No names: the server is stopped and its config removed.
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


def key_file(settings: Settings) -> Path:
    """Beside the config, in the folder CottenDNS's group reads."""

    return Path(str(settings.cottendns_config_file)).with_name("key")


def render_cottendns_config(settings: Settings, domains: list[str]) -> str:
    host, _, port = settings.cottendns_listen.rpartition(":")
    return "\n".join(
        [
            "# Rendered by nebula-agent from the control plane's DNS tunnel settings.",
            "DOMAIN = [" + ", ".join(_quote(name) for name in domains) + "]",
            # One fixed target: this server's VLESS Encryption inbound.
            'PROTOCOL_TYPE = "TCP"',
            'FORWARD_IP = "127.0.0.1"',
            f"FORWARD_PORT = {settings.xray_vlessenc_port}",
            f"UDP_HOST = {_quote(host)}",
            f"UDP_PORT = {port}",
            "TCP_LISTENER_ENABLED = true",
            # AES-256-GCM only: no other method is tried.
            "DATA_ENCRYPTION_METHOD = 5",
            "ENCRYPTION_AUTO_DETECT = false",
            f"ENCRYPTION_KEY_FILE = {_quote(str(key_file(settings)))}",
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


def _remove(path: Path) -> bool:
    try:
        path.unlink()
    except FileNotFoundError:
        return False
    return True


async def _systemctl(verb: str) -> None:
    result = await run_fixed_argv([_SYSTEMCTL_BINARY, verb, _UNIT], timeout_seconds=30)
    if result.returncode != 0:
        _LOGGER.warning("%s %s failed: %s", verb, _UNIT, result.stderr.decode(errors="replace"))


async def apply_cottendns(settings: Settings, domains: list[str], key: str) -> bool:
    """Serve these names with this key, or nothing when there are no names.
    True when something changed (and the server was restarted or stopped)."""

    config = Path(str(settings.cottendns_config_file))
    if not domains:
        removed = await asyncio.to_thread(_remove, config)
        await asyncio.to_thread(_remove, key_file(settings))
        if removed:
            await _systemctl("stop")
        return removed
    changed = await asyncio.to_thread(_write_if_changed, key_file(settings), key + "\n")
    changed |= await asyncio.to_thread(
        _write_if_changed, config, render_cottendns_config(settings, domains)
    )
    if changed:
        await _systemctl("restart")
    return changed
