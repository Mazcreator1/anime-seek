import os
import smtplib
from datetime import datetime
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText

# Use ONE settings source
SENDGRID_API_KEY = os.getenv("SENDGRID_API_KEY", "").strip()
FRONTEND_URL = os.getenv("FRONTEND_URL", "https://anime-seek.com").rstrip("/")

SENDGRID_HOST = os.getenv("SENDGRID_HOST", "smtp.sendgrid.net")
SENDGRID_PORT = int(os.getenv("SENDGRID_PORT", "465"))  # 465 SSL, 587 STARTTLS


def _send(to_email: str, subject: str, text: str, html: str) -> None:
    if not SENDGRID_API_KEY:
        raise RuntimeError("SENDGRID_API_KEY is missing/empty in environment")

    msg = MIMEMultipart("alternative")
    msg["Subject"] = subject
    msg["From"] = "Anime Seek <no-reply@anime-seek.com>"
    msg["To"] = to_email

    msg.attach(MIMEText(text, "plain"))
    msg.attach(MIMEText(html, "html"))

    # 465 = implicit SSL, 587 = STARTTLS
    if SENDGRID_PORT == 465:
        with smtplib.SMTP_SSL(SENDGRID_HOST, SENDGRID_PORT) as server:
            server.login("apikey", SENDGRID_API_KEY)
            server.send_message(msg)
    else:
        with smtplib.SMTP(SENDGRID_HOST, SENDGRID_PORT) as server:
            server.ehlo()
            server.starttls()
            server.ehlo()
            server.login("apikey", SENDGRID_API_KEY)
            server.send_message(msg)


def send_verification_email(to_email: str, token: str) -> None:
    link = f"{FRONTEND_URL}/fastapi/auth/verify-email?token={token}"

    subject = "Welcome to Anime Seek — Please Confirm Your Email"
    text = f"""Hello!

Thanks for signing up for Anime Seek. Verify your email here:

{link}

If you didn’t sign up, ignore this email.

Cheers,
The Anime Seek Team
"""
    html = f"""<!DOCTYPE html>
<html><body style="font-family:Arial,sans-serif;color:#333;">
  <h2>Anime Seek</h2>
  <p>Thanks for joining. Click to verify:</p>
  <p><a href="{link}">Verify My Email</a></p>
  <p style="color:#777;font-size:12px;">© {datetime.utcnow().year} Anime Seek</p>
</body></html>"""

    _send(to_email, subject, text, html)


def send_password_reset_email(to_email: str, token: str) -> None:
    link = f"{FRONTEND_URL}/fastapi/auth/reset-password?token={token}"

    subject = "Anime Seek — Reset Your Password"
    text = f"""Hello!

You requested a password reset. Reset it here:

{link}

If you didn’t request this, ignore this email.

Cheers,
The Anime Seek Team
"""
    html = f"""<!DOCTYPE html>
<html><body style="font-family:Arial,sans-serif;color:#333;">
  <h2>Anime Seek</h2>
  <p>Click to reset your password:</p>
  <p><a href="{link}">Reset Password</a></p>
  <p style="color:#777;font-size:12px;">© {datetime.utcnow().year} Anime Seek</p>
</body></html>"""

    _send(to_email, subject, text, html)


if __name__ == "__main__":
    print("[debug] FRONTEND_URL =", FRONTEND_URL)
    print("[debug] SENDGRID_HOST =", SENDGRID_HOST)
    print("[debug] SENDGRID_PORT =", SENDGRID_PORT)
    print("[debug] SENDGRID_API_KEY present?", bool(SENDGRID_API_KEY))
