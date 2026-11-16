import pytest

from nebula_worker.templates import UnknownTemplate, render


def test_account_request_review_includes_request_id() -> None:
    rendered = render("account_request_review", {"account_request_id": "canary-id"})

    assert "canary-id" in rendered.body
    assert "review" in rendered.subject.lower()
    assert "admin panel" not in rendered.body


def test_account_request_review_links_to_the_panel() -> None:
    rendered = render(
        "account_request_review",
        {
            "account_request_id": "canary-id",
            "review_url": "https://panel.example.com:8444/requests",
        },
    )

    assert "https://panel.example.com:8444/requests" in rendered.body


def test_user_activation_includes_token_and_expiry() -> None:
    rendered = render(
        "user_activation", {"token": "v1.activation-canary", "expires_at": "2026-08-01T00:00:00Z"}
    )

    assert "v1.activation-canary" in rendered.body
    assert "2026-08-01T00:00:00Z" in rendered.body


def test_password_reset_includes_token_and_expiry() -> None:
    rendered = render(
        "password_reset", {"token": "v1.reset-canary", "expires_at": "2026-08-01T00:00:00Z"}
    )

    assert "v1.reset-canary" in rendered.body


def test_request_rejected_needs_no_payload() -> None:
    rendered = render("request_rejected", {})

    assert "not approved" in rendered.body


def test_unknown_template_code_is_rejected() -> None:
    with pytest.raises(UnknownTemplate):
        render("something_else", {})


def test_user_activation_names_the_account_and_how_to_use_the_code() -> None:
    """The code alone left two real questions unanswered -- which account this
    is for, and what to do with a code in an app that only asks for a password
    -- so both identifiers and the app's own labels have to appear."""

    rendered = render(
        "user_activation",
        {
            "token": "v1.activation-canary",
            "expires_at": "2026-08-01T00:00:00Z",
            "username": "baba",
            "email": "user@example.com",
        },
    )

    assert "baba" in rendered.body
    assert "user@example.com" in rendered.body
    # Must match the sign-in screen's own label, or the instruction sends the
    # reader looking for a control that does not exist.
    assert "Have an activation code? Activate" in rendered.body
    # The recipient sets the password; saying so prevents the previous reading
    # that one had been issued and was missing from the email.
    assert "choose your own password" in rendered.body.lower()


def test_user_activation_omits_the_username_line_when_there_is_none() -> None:
    """Username is optional on an account request, so a blank labelled line
    would be worse than no line."""

    rendered = render(
        "user_activation",
        {
            "token": "v1.activation-canary",
            "expires_at": "2026-08-01T00:00:00Z",
            "username": "",
            "email": "user@example.com",
        },
    )

    assert "Username:" not in rendered.body
    assert "user@example.com" in rendered.body


@pytest.mark.parametrize(
    ("code", "payload"),
    [
        ("account_request_review", {"account_request_id": "r"}),
        ("user_activation", {"token": "t", "expires_at": "x", "email": "e@x"}),
        ("password_reset", {"token": "t", "expires_at": "x"}),
        ("request_rejected", {}),
    ],
)
def test_every_email_has_an_html_part(code: str, payload: dict[str, str]) -> None:
    rendered = render(code, payload)

    assert rendered.html is not None
    assert rendered.html.startswith("<!DOCTYPE html>")
    assert "<h1" in rendered.html


def test_html_carries_the_code_and_escapes_every_value() -> None:
    rendered = render(
        "user_activation",
        {
            "token": "K7QF-29XM",
            "expires_at": "2026-11-17",
            "email": "<script>@example.com",
            "username": 'a"b',
        },
    )

    assert rendered.html is not None
    assert "K7QF-29XM" in rendered.html
    assert "<script>" not in rendered.html
    assert "&lt;script&gt;@example.com" in rendered.html
    assert "a&quot;b" in rendered.html


def test_review_button_only_with_a_review_url() -> None:
    without = render("account_request_review", {"account_request_id": "r"})
    with_url = render(
        "account_request_review",
        {"account_request_id": "r", "review_url": "https://panel.example.com/requests"},
    )

    assert without.html is not None and "<a " not in without.html
    assert with_url.html is not None
    assert 'href="https://panel.example.com/requests"' in with_url.html


def test_reset_html_names_the_app_screen() -> None:
    rendered = render("password_reset", {"token": "t", "expires_at": "x"})

    assert rendered.html is not None
    assert "Check your email" in rendered.html
    # The plain text keeps its words.
    assert "Check your email" not in rendered.body
