"""Cuts Xray's geoip.dat and geosite.dat down to the entries the app uses.

The full files are 26 MB and list every country and category; the app's
routing names only geoip:ir, geoip:private and geosite:category-ir
(lib/core/xray/), and the desktop DNS tunnel reads geoip IR. Everything else
was carried in every build for nothing.

    python tool/trim_geodata.py <dir or .aar> ...   # trims in place
    python tool/trim_geodata.py --selftest

Both files are protobuf lists: field 1 repeated, each entry a message whose
field 1 is its code (GeoIPList/GeoIP, GeoSiteList/GeoSite). A code the app
needs and the file lacks stops the build.
"""

from __future__ import annotations

import io
import sys
import zipfile
from pathlib import Path

KEEP = {
    "geoip.dat": {"IR", "PRIVATE"},
    "geosite.dat": {"CATEGORY-IR"},
}


def _varint(data: bytes, at: int) -> tuple[int, int]:
    value = shift = 0
    while True:
        byte = data[at]
        at += 1
        value |= (byte & 0x7F) << shift
        if byte < 0x80:
            return value, at
        shift += 7


def _entries(data: bytes):
    """(code, raw field bytes) for each top-level field-1 entry."""
    at = 0
    while at < len(data):
        start = at
        key, at = _varint(data, at)
        if key != 0x0A:  # field 1, length-delimited
            raise ValueError(f"unexpected field key {key} at {start}")
        length, at = _varint(data, at)
        body = data[at: at + length]
        at += length
        inner_key, inner_at = _varint(body, 0)
        if inner_key != 0x0A:
            raise ValueError("entry without a code")
        code_length, inner_at = _varint(body, inner_at)
        code = body[inner_at: inner_at + code_length].decode().upper()
        yield code, data[start:at]


def trim(name: str, data: bytes) -> bytes:
    keep = KEEP[name]
    kept = {code: raw for code, raw in _entries(data) if code in keep}
    missing = keep - kept.keys()
    if missing:
        raise SystemExit(f"{name} has no {', '.join(sorted(missing))}")
    return b"".join(kept[code] for code in sorted(kept))


def trim_path(path: Path) -> None:
    if path.suffix == ".aar":
        with zipfile.ZipFile(path) as src:
            items = [(info, src.read(info)) for info in src.infolist()]
        out = io.BytesIO()
        with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as dst:
            for info, data in items:
                name = info.filename.rsplit("/", 1)[-1]
                if info.filename.startswith("assets/") and name in KEEP:
                    before = len(data)
                    data = trim(name, data)
                    print(f"  {path.name}:{info.filename} {before} -> {len(data)} bytes")
                dst.writestr(info, data)
        path.write_bytes(out.getvalue())
        return
    for name in KEEP:
        file = path / name
        before = file.stat().st_size
        file.write_bytes(trim(name, file.read_bytes()))
        print(f"  {file} {before} -> {file.stat().st_size} bytes")


def _selftest() -> None:
    def entry(code: str, payload: bytes) -> bytes:
        body = b"\x0a" + bytes([len(code)]) + code.encode() + payload
        return b"\x0a" + bytes([len(body)]) + body

    data = entry("CN", b"\x12\x02xy") + entry("ir", b"\x12\x01z") + entry("PRIVATE", b"")
    assert trim("geoip.dat", data) == entry("ir", b"\x12\x01z") + entry("PRIVATE", b"")
    try:
        trim("geosite.dat", data)
    except SystemExit as missing:
        assert "CATEGORY-IR" in str(missing)
    else:
        raise AssertionError("a missing code must stop the build")
    print("selftest ok")


if __name__ == "__main__":
    if sys.argv[1:] == ["--selftest"]:
        _selftest()
    else:
        for argument in sys.argv[1:]:
            trim_path(Path(argument))
