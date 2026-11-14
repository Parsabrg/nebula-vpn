"""Fixed templates for the closed `email_deliveries` vocabulary.

Each email is plain text plus the same words as HTML (DESIGN_SPEC section
6, Emails), sent together as multipart/alternative: the HTML adds a
heading, the code set large in mono, and the review email's button. Every
payload value is escaped before it reaches the HTML.
"""

from dataclasses import dataclass
from html import escape


class UnknownTemplate(ValueError):
    """Raised for a `template_code` outside the reviewed vocabulary."""


@dataclass(frozen=True, slots=True)
class RenderedEmail:
    subject: str
    body: str
    html: str | None = None


# Inline styles only: mail clients drop <style> blocks and web fonts, so the
# fonts fall back to the reader's own. Colours meet WCAG AA on white.
_SANS = "Geist,-apple-system,'Segoe UI',Roboto,Helvetica,Arial,sans-serif"
_MONO = "'Geist Mono',ui-monospace,SFMono-Regular,Menlo,Consolas,monospace"
_INK = "#101014"
_BODY = "#3E3E48"
_MUTED = "#55555F"
_LINE = "#E1E1E7"
_ACCENT = "#2A46BE"


def _p(text: str, *, muted: bool = False) -> str:
    colour = _MUTED if muted else _BODY
    return (
        f'<p style="margin:12px 0 0;font:400 15px/24px {_SANS};color:{colour}">{escape(text)}</p>'
    )


def _code(label: str, code: str, note: str) -> str:
    return (
        f'<div style="margin-top:24px;padding:18px 20px;border-radius:10px;'
        f'background:#F4F4F7;border:1px solid {_LINE}">'
        f'<div style="font:500 12px/16px {_SANS};color:{_MUTED}">{escape(label)}</div>'
        f'<div style="margin-top:6px;font:500 28px/36px {_MONO};letter-spacing:3px;'
        f'color:{_INK}">{escape(code)}</div>'
        f'<div style="margin-top:6px;font:400 13px/19px {_SANS};color:{_MUTED}">'
        f"{escape(note)}</div></div>"
    )


def _page(heading: str, content: str) -> str:
    return (
        '<!DOCTYPE html><html lang="en"><head><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width,initial-scale=1">'
        f"<title>{escape(heading)}</title></head>"
        f'<body style="margin:0;padding:32px 16px;background:#F4F4F7">'
        f'<div style="max-width:520px;margin:0 auto;background:#FFFFFF;'
        f'border:1px solid {_LINE};border-radius:12px;padding:36px 32px 32px;color:{_INK}">'
        f'<div style="font:500 13px/18px {_MONO};letter-spacing:2px;color:{_MUTED}">NEBULA</div>'
        f'<h1 style="margin:20px 0 0;font:600 24px/30px {_SANS};letter-spacing:-0.4px;'
        f'color:{_INK}">{escape(heading)}</h1>'
        f"{content}</div>"
        f'<div style="max-width:520px;margin:16px auto 0;font:400 12px/18px {_SANS};'
        f'color:{_MUTED};text-align:center">Nebula VPN</div>'
        "</body></html>"
    )


def render(template_code: str, payload: dict[str, str]) -> RenderedEmail:
    if template_code == "account_request_review":
        request_id = payload.get("account_request_id", "")
        # Absent from payloads staged before the API sent it.
        review_url = payload.get("review_url", "")
        review = f"Review it in the admin panel:\n  {review_url}\n\n" if review_url else ""
        button = ""
        if review_url:
            url = escape(review_url, quote=True)
            button = (
                f'<a href="{url}" style="margin-top:24px;display:inline-block;'
                f"padding:12px 20px;border-radius:10px;background:{_ACCENT};"
                f'color:#FFFFFF;font:600 15px {_SANS};text-decoration:none">'
                "Review it in the admin panel</a>"
                f'<p style="margin:16px 0 0;font:400 15px/24px {_SANS};color:{_MUTED}">'
                f'Or open this address: <span style="font-family:{_MONO};font-size:13px;'
                f'color:{_INK};word-break:break-all">{escape(review_url)}</span></p>'
            )
        return RenderedEmail(
            subject="New Nebula account request pending review",
            body=(
                "A new account request is waiting for review.\n\n"
                f"{review}Request ID: {request_id}\n"
            ),
            html=_page(
                "A new account request is waiting for review.",
                button
                + f'<div style="margin-top:20px;padding-top:16px;border-top:1px solid {_LINE};'
                f'font:400 13px/19px {_SANS};color:{_MUTED}">Request ID<br>'
                f'<span style="font-family:{_MONO};color:{_INK};word-break:break-all">'
                f"{escape(request_id)}</span></div>",
            ),
        )
    if template_code == "user_activation":
        token = payload.get("token", "")
        expires_at = payload.get("expires_at", "")
        username = payload.get("username", "")
        email = payload.get("email", "")
        # Names the account, then gives one instruction per screen the reader
        # actually sees. The earlier version sent only the code, leaving two
        # real questions unanswered: which account this is for, and what to do
        # with a code when the app only asks for a password. The quoted labels
        # below match the app's own exactly, so they can be followed literally.
        identifiers = f"  Email:    {email}\n"
        if username:
            identifiers += f"  Username: {username}\n"
        account_rows = (
            f'<tr><td style="padding:3px 12px 3px 0;color:{_MUTED}">Email</td>'
            f'<td style="font-family:{_MONO}">{escape(email)}</td></tr>'
        )
        if username:
            account_rows += (
                f'<tr><td style="padding:3px 12px 3px 0;color:{_MUTED}">Username</td>'
                f'<td style="font-family:{_MONO}">{escape(username)}</td></tr>'
            )
        steps = "".join(
            f"<li>{escape(step)}</li>"
            for step in (
                "Open the Nebula app.",
                "On the sign-in screen, tap “Have an activation code? Activate”.",
                "Enter the activation code below.",
                "Choose the password you want, then tap “Activate”.",
            )
        )
        return RenderedEmail(
            subject="Activate your Nebula account",
            body=(
                "Your Nebula account request was approved.\n\n"
                "This account:\n"
                f"{identifiers}\n"
                "To finish setting it up:\n\n"
                "  1. Open the Nebula app.\n"
                '  2. On the sign-in screen, tap "Have an activation code? '
                'Activate".\n'
                "  3. Enter the activation code below.\n"
                '  4. Choose the password you want, then tap "Activate".\n\n'
                f"Activation code:\n  {token}\n\n"
                # Said outright because the previous email's silence on it read
                # as "a password was issued and is missing from this email".
                "You choose your own password in step 4. No password has been\n"
                "created for you, and nobody here can see or set it.\n\n"
                "After activating, sign in with the password you just chose.\n\n"
                f"This code works once and expires at {expires_at}.\n"
                "If it expires, ask an administrator to approve a new request.\n"
            ),
            html=_page(
                "Your Nebula account request was approved.",
                f'<div style="margin-top:20px;padding:14px 16px;border:1px solid {_LINE};'
                f'border-radius:10px"><div style="font:500 12px/16px {_SANS};color:{_MUTED}">'
                "This account</div>"
                f'<table role="presentation" style="margin-top:8px;border-collapse:collapse;'
                f'font:400 14px/20px {_SANS};color:{_INK}">{account_rows}</table></div>'
                f'<h2 style="margin:24px 0 0;font:600 16px/22px {_SANS};color:{_INK}">'
                "To finish setting it up</h2>"
                f'<ol style="margin:10px 0 0;padding-left:22px;font:400 15px/24px {_SANS};'
                f'color:{_BODY}">{steps}</ol>'
                + _code(
                    "Activation code",
                    token,
                    f"This code works once and expires at {expires_at}.",
                )
                + _p(
                    "You choose your own password in step 4. No password has been "
                    "created for you, and nobody here can see or set it."
                )
                + _p("After activating, sign in with the password you just chose.")
                + _p(
                    "If it expires, ask an administrator to approve a new request.",
                    muted=True,
                ),
            ),
        )
    if template_code == "password_reset":
        token = payload.get("token", "")
        expires_at = payload.get("expires_at", "")
        return RenderedEmail(
            subject="Reset your Nebula password",
            body=(
                "A password reset was requested for your Nebula account.\n\n"
                f"Reset code: {token}\n"
                f"This code expires at {expires_at}.\n"
                "If you did not request this, no action is needed.\n"
            ),
            html=_page(
                "Reset your password",
                _p("A password reset was requested for your Nebula account.")
                + _code("Reset code", token, f"This code expires at {expires_at}.")
                + _p(
                    "Enter it in the app on the “Check your email” screen, "
                    "with the new password you want."
                )
                + _p("If you did not request this, no action is needed.", muted=True),
            ),
        )
    if template_code == "request_rejected":
        return RenderedEmail(
            subject="Your Nebula account request was not approved",
            body="Your Nebula account request was reviewed and was not approved.\n",
            html=_page(
                "Your request was not approved",
                _p("Your Nebula account request was reviewed and was not approved."),
            ),
        )
    raise UnknownTemplate(template_code)
