"""Forwarded receipts: email a receipt to receipts@dataeaver.ca and it's
read and added to your account.

Who it belongs to:
* sent to your personal address, ``receipts+<token>@…`` (from any inbox), or
* sent from your account's verified email, when the receiving server vouches
  for the sender (DMARC, or DKIM/SPF aligned with the From domain), so nobody
  can drop receipts into your account by faking your address.

What's read: the first PDF or image attachment (PDFs as in services/pdf.py),
else the email's own text (HTML receipts from Uber, Amazon…). The mailbox is
polled over IMAP; handled mail is marked read. Off until IMAP_PASSWORD is set.
"""

import asyncio
import email
import html
import imaplib
import logging
import re
import secrets
from email.message import Message
from email.utils import getaddresses, parseaddr
from html.parser import HTMLParser

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession
from starlette.concurrency import run_in_threadpool

from app.config import get_settings
from app.models import Activity, User
from app.services import notify_prefs, pdf, push, split_store
from app.services.azure_openai import ExtractionError
from app.services.extraction import process_receipt

log = logging.getLogger(__name__)

MAX_BYTES = 12_000_000


def enabled() -> bool:
    s = get_settings()
    return bool(s.imap_password and s.receipts_inbox_address)


async def personal_address(session: AsyncSession, user: User) -> str:
    if not user.inbox_token:
        user.inbox_token = secrets.token_hex(5)
        await session.commit()
    local, _, domain = get_settings().receipts_inbox_address.partition("@")
    return f"{local}+{user.inbox_token}@{domain}"


# ───────────────────────── reading a message ─────────────────────────


class _Text(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.lines: list[str] = []
        self._skip = 0

    def handle_starttag(self, tag, attrs):
        if tag in ("script", "style", "head"):
            self._skip += 1
        if tag in ("br", "p", "div", "tr", "li", "h1", "h2", "h3", "table"):
            self.lines.append("\n")

    def handle_endtag(self, tag):
        if tag in ("script", "style", "head") and self._skip:
            self._skip -= 1
        if tag in ("td", "th"):
            self.lines.append("  ")

    def handle_data(self, data):
        if not self._skip:
            self.lines.append(data)


def html_to_lines(markup: str) -> list[str]:
    parser = _Text()
    parser.feed(markup)
    text = html.unescape("".join(parser.lines))
    return [" ".join(line.split()) for line in text.splitlines() if line.strip()]


def content(msg: Message) -> tuple[bytes, list[str]]:
    """(image bytes or b"", text lines) — an attachment wins over the body."""
    body_html = body_text = None
    for part in msg.walk():
        if part.is_multipart():
            continue
        ctype = part.get_content_type()
        payload = part.get_payload(decode=True) or b""
        name = (part.get_filename() or "").lower()
        if (ctype == "application/pdf" or name.endswith(".pdf")) and payload:
            image, lines = pdf.to_image_and_text(payload[:MAX_BYTES])
            return image, lines
        if ctype.startswith("image/") and len(payload) > 20_000 and ctype != "image/gif":
            # Big enough to be a photo of a receipt, not a logo or tracking pixel.
            return payload[:MAX_BYTES], []
        if ctype == "text/html" and body_html is None:
            body_html = payload.decode(part.get_content_charset() or "utf-8", "replace")
        elif ctype == "text/plain" and body_text is None:
            body_text = payload.decode(part.get_content_charset() or "utf-8", "replace")
    if body_html:
        return b"", html_to_lines(body_html)[:300]
    lines = [line.strip() for line in (body_text or "").splitlines() if line.strip()]
    return b"", lines[:300]


def _domain(address: str) -> str:
    return address.rpartition("@")[2].lower()


def sender_vouched(msg: Message, sender: str) -> bool:
    """The receiving server says the From address really sent it."""
    domain = _domain(sender)
    results = " ".join(msg.get_all("Authentication-Results") or []).lower()
    if "dmarc=pass" in results:
        return True
    for d in re.findall(r"dkim=pass[^;]*header\.(?:d|i)=@?([\w.-]+)", results):
        if d.lstrip("@") == domain or domain.endswith("." + d):
            return True
    for d in re.findall(r"spf=pass[^;]*smtp\.mailfrom=(?:[^@\s;]*@)?([\w.-]+)", results):
        if d == domain:
            return True
    return False


async def owner(session: AsyncSession, msg: Message) -> User | None:
    s = get_settings()
    local = s.receipts_inbox_address.partition("@")[0].lower()
    recipients = [
        a
        for _, a in getaddresses(
            msg.get_all("To", []) + msg.get_all("Cc", []) + msg.get_all("Delivered-To", [])
        )
    ]
    for address in recipients:
        m = re.match(rf"^{re.escape(local)}\+([0-9a-f]{{6,32}})@", address.lower())
        if m:
            user = await session.scalar(select(User).where(User.inbox_token == m.group(1)))
            if user is not None:
                return user
    sender = parseaddr(msg.get("From", ""))[1].lower()
    if sender and sender_vouched(msg, sender):
        return await session.scalar(
            select(User).where(func.lower(User.email) == sender, User.email_verified.is_(True))
        )
    return None


async def handle(session: AsyncSession, raw: bytes, extractor) -> str:
    """Add one forwarded email's receipt. Returns what happened (for logs)."""
    msg = email.message_from_bytes(raw)
    user = await owner(session, msg)
    if user is None:
        return "no account"
    try:
        image, lines = content(msg)
    except pdf.PdfError:
        return "bad pdf"
    if not image and not lines:
        return "empty"
    subject = (msg.get("Subject") or "").strip()
    if not image and subject:
        lines = [f"Subject: {subject}", *lines]
    try:
        receipt = await process_receipt(
            session=session,
            user=user,
            image_bytes=image,
            ocr_lines=lines,
            request_id=f"mail-{secrets.token_hex(8)}",
            extractor=extractor,
        )
    except ExtractionError:
        return "extraction failed"
    store = receipt.merchant or "A receipt"
    amount = split_store._money_text(receipt.total, receipt.currency)
    category = (receipt.category_slug or "other").replace("_", " ").capitalize()
    day = receipt.purchased_at
    when = f"{day:%b} {day.day}" if day else None
    text = f"added {store}, {amount}" + (f" on {when}" if when else "") + ", from your email"
    session.add(
        Activity(
            user_id=user.id, actor_name="Tally", kind="emailed", text=text, receipt_id=receipt.id
        )
    )
    if notify_prefs.allowed(user, "emailed", "push"):
        # "Receipt added from your email" / "Uber · $15.94 · Nov 2 · Transport"
        await push.send(
            session,
            [user.id],
            " · ".join(part for part in (store, amount, when, category) if part),
            title="Receipt added from your email",
            link=f"receipts/{receipt.id}",
            target={"receipt": receipt.id},
        )
    await session.commit()
    return "added"


# ───────────────────────── polling the mailbox ─────────────────────────


def _fetch_unseen(limit: int = 20) -> list[tuple[bytes, bytes]]:
    s = get_settings()
    box = imaplib.IMAP4_SSL(s.imap_host, s.imap_port)
    try:
        box.login(s.receipts_inbox_address, s.imap_password)
        box.select("INBOX")
        _, ids = box.search(None, "UNSEEN")
        out = []
        for num in (ids[0].split() if ids and ids[0] else [])[:limit]:
            _, data = box.fetch(num, "(BODY.PEEK[])")
            if data and isinstance(data[0], tuple):
                out.append((num, data[0][1]))
        return out
    finally:
        try:
            box.logout()
        except Exception:  # noqa: BLE001
            pass


def _mark_seen(nums: list[bytes]) -> None:
    if not nums:
        return
    s = get_settings()
    box = imaplib.IMAP4_SSL(s.imap_host, s.imap_port)
    try:
        box.login(s.receipts_inbox_address, s.imap_password)
        box.select("INBOX")
        for num in nums:
            box.store(num, "+FLAGS", "\\Seen")
    finally:
        try:
            box.logout()
        except Exception:  # noqa: BLE001
            pass


async def run_forever(sessionmaker, extractor_factory, every_seconds: int = 120) -> None:
    """One replica reads at a time is fine: a message is marked read once
    handled, and a rare double read only re-adds a receipt (rows are cheap
    to delete). Errors back off to the next round."""
    await asyncio.sleep(45)
    while True:
        if enabled():
            try:
                messages = await run_in_threadpool(_fetch_unseen)
                done = []
                for num, raw in messages:
                    if len(raw) > MAX_BYTES * 2:
                        done.append(num)
                        continue
                    async with sessionmaker() as session:
                        result = await handle(session, raw, extractor_factory())
                    log.info("forwarded receipt: %s", result)
                    done.append(num)
                await run_in_threadpool(_mark_seen, done)
            except Exception:  # noqa: BLE001 - next round
                log.warning("receipts inbox run failed", exc_info=True)
        await asyncio.sleep(every_seconds)
