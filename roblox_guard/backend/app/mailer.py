"""Best-effort SMTP relay for customer bug reports.

Every report is persisted to the `bug_reports` table regardless of whether
email delivery succeeds — the database, not the inbox, is the durable
record (see db.py, main.py `/support/bug-report`). Set RG_SMTP_HOST (plus
RG_SMTP_USER/RG_SMTP_PASSWORD as needed) to also relay each report by email
to RG_SUPPORT_EMAIL. With no SMTP host configured this is a no-op — reports
still land in the log, just not in an inbox until an operator configures it.
"""

import logging
import smtplib
from email.message import EmailMessage

from .config import Settings

log = logging.getLogger("roblox_guard.mailer")


def send_bug_report_email(settings: Settings, report: dict) -> bool:
    if not settings.smtp_host or not settings.support_email:
        return False

    msg = EmailMessage()
    msg["Subject"] = f"[RobloxGuard] Bug report: {report['summary'][:80]}"
    msg["From"] = settings.smtp_from or settings.smtp_user or settings.support_email
    msg["To"] = settings.support_email
    if report.get("contact_email"):
        msg["Reply-To"] = report["contact_email"]
    msg.set_content(
        f"Source: {report['source']}\n"
        f"Reported at: {report['created_at']}\n"
        f"Contact email: {report.get('contact_email') or '(not provided)'}\n"
        f"Context: {report.get('context')}\n\n"
        f"{report.get('details', '')}\n"
    )

    try:
        with smtplib.SMTP(settings.smtp_host, settings.smtp_port, timeout=10) as smtp:
            if settings.smtp_use_tls:
                smtp.starttls()
            if settings.smtp_user:
                smtp.login(settings.smtp_user, settings.smtp_password)
            smtp.send_message(msg)
        return True
    except Exception as error:
        log.warning("Failed to email bug report %s: %s", report.get("id"), error)
        return False
