"""Writes site/privacy.html and site/terms.html from docs/privacy.md and
docs/terms.md, so the website says what the repository and the app say.

    python site/build_legal.py           # write the pages
    python site/build_legal.py --check   # fail if they are out of date

Only the markdown those two files use: `#`/`##` headings, paragraphs, `-`
lists nested by indent, tables, and bold, code and link marks.
"""

from __future__ import annotations

import html
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SITE = "https://parsabrg.github.io/nebula-vpn/"
PAGES = {
    "privacy": ("docs/privacy.md", "Privacy policy", "What Nebula VPN stores, for how long, and what its apps send where."),
    "terms": ("docs/terms.md", "Terms of use", "Terms for using the Nebula VPN apps and the servers they reach."),
}
LINKS = {"privacy.md": "privacy.html", "terms.md": "terms.html"}


def inline(text: str) -> str:
    out = html.escape(text, quote=False)
    out = re.sub(r"`([^`]+)`", r"<code>\1</code>", out)
    out = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", out)

    def link(match: re.Match[str]) -> str:
        target = LINKS.get(match.group(2), match.group(2))
        return f'<a href="{html.escape(target)}">{match.group(1)}</a>'

    return re.sub(r"\[([^\]]+)\]\(([^)]+)\)", link, out)


def render(markdown: str) -> tuple[str, str]:
    lines = markdown.replace("\r\n", "\n").split("\n")
    out: list[str] = []
    title = ""
    paragraph: list[str] = []
    depth = 0  # open <ul> levels
    bullet = re.compile(r"^(\s*)- (.*)$")

    def flush() -> None:
        if paragraph:
            out.append(f"<p>{inline(' '.join(paragraph))}</p>")
            paragraph.clear()

    def close_lists(to: int = 0) -> None:
        nonlocal depth
        while depth > to:
            out.append("</li></ul>")
            depth -= 1

    i = 0
    while i < len(lines):
        line = lines[i]
        item = bullet.match(line)
        if not line.strip():
            flush()
            if not (i + 1 < len(lines) and bullet.match(lines[i + 1])):
                close_lists()
        elif line.startswith("# "):
            flush()
            close_lists()
            title = line[2:].strip()
        elif line.startswith("## "):
            flush()
            close_lists()
            out.append(f"<h2>{inline(line[3:].strip())}</h2>")
        elif line.startswith("|"):
            flush()
            close_lists()
            rows = []
            while i < len(lines) and lines[i].startswith("|"):
                cells = [c.strip() for c in lines[i].strip()[1:-1].split("|")]
                if not all(re.fullmatch(r":?-+:?", c) for c in cells):
                    rows.append(cells)
                i += 1
            i -= 1
            head = "".join(f"<th>{inline(c)}</th>" for c in rows[0])
            body = "".join(
                "<tr>" + "".join(f"<td>{inline(c)}</td>" for c in row) + "</tr>"
                for row in rows[1:]
            )
            out.append(f"<table><thead><tr>{head}</tr></thead><tbody>{body}</tbody></table>")
        elif item:
            flush()
            level = len(item.group(1)) // 2 + 1
            words = [item.group(2)]
            while (
                i + 1 < len(lines)
                and lines[i + 1].startswith(" " * (len(item.group(1)) + 2))
                and not bullet.match(lines[i + 1])
            ):
                i += 1
                words.append(lines[i].strip())
            if level > depth:
                while depth < level:
                    out.append("<ul><li>")
                    depth += 1
            else:
                close_lists(level)
                out.append("</li><li>")
            out.append(inline(" ".join(words)))
        else:
            close_lists()
            paragraph.append(line.strip())
        i += 1
    flush()
    close_lists()
    return title, "\n".join(out)


def page(name: str) -> str:
    source, heading, description = PAGES[name]
    title, body = render((ROOT / source).read_text(encoding="utf-8"))
    assert title == heading, (source, title)
    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{heading} – Nebula VPN</title>
<meta name="description" content="{description}">
<link rel="canonical" href="{SITE}{name}.html">
<link rel="icon" type="image/png" href="favicon.png">
<style>
  :root {{ --bg: #f7f7fa; --fg: #15151c; --muted: #5b5b6b; --card: #ffffff; --line: #e3e3ea; --accent: #4f63e7; }}
  @media (prefers-color-scheme: dark) {{
    :root {{ --bg: #0b0b10; --fg: #f1f1f5; --muted: #a0a0b2; --card: #15151d; --line: #26263a; --accent: #8193ff; }}
  }}
  * {{ box-sizing: border-box; }}
  body {{ margin: 0; background: var(--bg); color: var(--fg); font: 17px/1.6 system-ui, -apple-system, "Segoe UI", Roboto, sans-serif; }}
  main {{ max-width: 860px; margin: 0 auto; padding: 40px 16px 64px; }}
  nav a {{ color: var(--muted); text-decoration: none; font-size: 15px; }}
  h1 {{ font-size: clamp(28px, 5vw, 40px); margin: 16px 0 8px; letter-spacing: -0.02em; }}
  h2 {{ margin: 36px 0 10px; font-size: 22px; }}
  ul {{ padding-inline-start: 22px; }}
  li {{ margin: 6px 0; }}
  a {{ color: var(--accent); }}
  code {{ font-size: 0.9em; overflow-wrap: anywhere; }}
  table {{ width: 100%; border-collapse: collapse; background: var(--card); border: 1px solid var(--line); border-radius: 12px; font-size: 15px; display: block; overflow-x: auto; }}
  th, td {{ text-align: start; vertical-align: top; padding: 10px 12px; border-bottom: 1px solid var(--line); }}
  footer {{ margin-top: 56px; color: var(--muted); font-size: 14px; }}
</style>
</head>
<body>
<main>
  <nav><a href="./">← Nebula VPN</a></nav>
  <h1>{heading}</h1>
{body}
  <footer>Generated from <a href="https://github.com/Parsabrg/nebula-vpn/blob/main/{source}">{source}</a>. <a href="privacy.html">Privacy policy</a> · <a href="terms.html">Terms of use</a></footer>
</main>
</body>
</html>
"""


def main() -> int:
    stale = []
    for name in PAGES:
        target = ROOT / "site" / f"{name}.html"
        text = page(name)
        if "--check" in sys.argv:
            # Line endings aside: a Windows checkout writes CRLF.
            if not target.exists() or target.read_text(encoding="utf-8").replace("\r\n", "\n") != text:
                stale.append(target.name)
        else:
            target.write_text(text, encoding="utf-8", newline="\n")
    if stale:
        print(f"Out of date: {', '.join(stale)}. Run python site/build_legal.py", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
