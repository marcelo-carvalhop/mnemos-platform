"""Confirmation email. No FastAPI here (§4.2).

Plain SMTP with STARTTLS, which is what Gmail's app passwords and every
transactional provider speak, so changing provider is a change of four
environment variables and no code. Without SMTP_HOST the link is logged: local
development needs the link, not a mail server.
"""

from __future__ import annotations

import logging
import smtplib
from email.message import EmailMessage
from email.utils import formataddr, parseaddr
from urllib.parse import quote

from app.config import get_settings

log = logging.getLogger("app.auth.mail")


def verification_link(token: str) -> str:
    base = get_settings().public_web_url.rstrip("/")
    return f"{base}/confirmar?token={quote(token)}"


_WRAP = (
    "font-family:system-ui,-apple-system,Segoe UI,Roboto,sans-serif;"
    "max-width:480px;margin:0 auto;padding:32px 24px;color:#1d1b18"
)
_BUTTON = (
    "display:inline-block;background:#1d1b18;color:#fff;text-decoration:none;"
    "padding:12px 22px;border-radius:10px;font-size:15px;font-weight:600"
)
_HTML = (
    f'<div style="{_WRAP}">'
    '<p style="font-size:20px;font-weight:600;margin:0 0 16px">Confirme seu e-mail</p>'
    '<p style="font-size:15px;line-height:1.55;margin:0 0 24px">'
    "Para ativar sua conta no Mnemos, toque no botão abaixo.</p>"
    f'<p style="margin:0 0 28px"><a href="{{link}}" style="{_BUTTON}">Confirmar e-mail</a></p>'
    '<p style="font-size:13px;line-height:1.5;color:#6b665e;margin:0">'
    "O link vale por 7 dias. Se você não criou esta conta, ignore este e-mail.</p>"
    "</div>"
)


def sender() -> str:
    """The From header: always "Mnemos <address>".

    MAIL_FROM may hold a bare address or a whole "Name <address>"; only the
    address is kept. Wrapping a full "Mnemos <...>" a second time produced
    `Mnemos <Mnemos>, <>`, which Gmail accepted and never delivered.
    """
    settings = get_settings()
    address = parseaddr(settings.mail_from or settings.smtp_user)[1]
    return formataddr(("Mnemos", address))


def _message(to: str, link: str) -> EmailMessage:
    msg = EmailMessage()
    msg["Subject"] = "Confirme seu e-mail no Mnemos"
    msg["From"] = sender()
    msg["To"] = to
    msg.set_content(
        "Olá!\n\n"
        "Para ativar sua conta no Mnemos, abra o link abaixo:\n\n"
        f"{link}\n\n"
        "O link vale por 7 dias. Se você não criou esta conta, ignore este e-mail.\n"
    )
    msg.add_alternative(_HTML.format(link=link), subtype="html")
    return msg


def send_verification(to: str, token: str) -> None:
    """Runs after the response (a background task): a slow or failing SMTP
    server must not turn a successful signup into an error. Failures are
    logged; the person can ask for the link again."""
    settings = get_settings()
    link = verification_link(token)

    if not settings.smtp_host:
        log.warning("SMTP not configured; confirmation link for %s: %s", to, link)
        return

    try:
        with smtplib.SMTP(settings.smtp_host, settings.smtp_port, timeout=20) as smtp:
            smtp.starttls()
            if settings.smtp_user:
                smtp.login(settings.smtp_user, settings.smtp_password)
            smtp.send_message(_message(to, link))
        log.info("confirmation email sent to %s", to)
    except (smtplib.SMTPException, OSError):
        log.exception("could not send the confirmation email to %s", to)
