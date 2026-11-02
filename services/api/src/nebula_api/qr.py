"""QR codes as SVG documents for the admin panel."""

import io

import segno


def qr_svg(text: str) -> str:
    """A whole SVG document, namespace included: the panel shows it as an
    image, and an SVG without its namespace does not render as one. Black on
    white whatever the panel's theme, which is what cameras read."""
    image = io.BytesIO()
    segno.make(text, error="m").save(
        image, kind="svg", scale=6, border=4, dark="black", light="white", xmldecl=False
    )
    return image.getvalue().decode("utf-8")
