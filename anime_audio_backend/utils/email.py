# anime_audio_backend/utils/email.py

import smtplib
from email.message import EmailMessage
from config import settings

def send_email(to: str, subject: str, body: str) -> None:
    """
    Send a plain‐text email via SMTP using your settings.
    """
    msg = EmailMessage()
    msg["Subject"] = subject
    msg["From"]    = settings.EMAIL_FROM
    msg["To"]      = to
    msg.set_content(body)

    # Connect & send
    with smtplib.SMTP(settings.SMTP_HOST, settings.SMTP_PORT) as server:
        server.starttls()  # upgrade to TLS
        server.login(settings.SMTP_USER, settings.SMTP_PASSWORD)
        server.send_message(msg)
