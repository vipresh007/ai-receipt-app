"""Forwarded receipts (services/inbox.py)."""

from email.message import EmailMessage

from sqlalchemy import select

from app.config import get_settings
from app.models import Activity, Receipt, User
from app.services import inbox
from tests.conftest import FakeExtractor
from tests.test_pdf_receipts import tiny_pdf


class Capturing(FakeExtractor):
    def __init__(self) -> None:
        self.calls: list[dict] = []

    def extract(self, **kwargs):
        self.calls.append(kwargs)
        return super().extract(**kwargs)


def mail(to: str, sender: str, *, auth: str = "", html: str = "", pdf: bytes = b"") -> bytes:
    msg = EmailMessage()
    msg["From"] = sender
    msg["To"] = to
    msg["Subject"] = "Your Uber receipt"
    if auth:
        msg["Authentication-Results"] = auth
    msg.set_content("Thanks for riding")
    if html:
        msg.add_alternative(html, subtype="html")
    if pdf:
        msg.add_attachment(pdf, maintype="application", subtype="pdf", filename="receipt.pdf")
    return msg.as_bytes()


async def _user(sessionmaker_, **kw) -> User:
    async with sessionmaker_() as session:
        user = (await session.scalars(select(User))).first()
        for k, v in kw.items():
            setattr(user, k, v)
        await session.commit()
        return user


async def test_personal_address_reads_the_pdf(sessionmaker_, test_user):
    await _user(sessionmaker_, inbox_token="abc123def0")
    extractor = Capturing()
    raw = mail(
        "receipts+abc123def0@dataeaver.ca",
        "someone@else.com",
        pdf=tiny_pdf("HYDRO ONE", "Due 96.40"),
    )
    async with sessionmaker_() as session:
        assert await inbox.handle(session, raw, extractor) == "added"
    assert extractor.calls[0]["image_bytes"][:3] == b"\xff\xd8\xff"
    assert extractor.calls[0]["ocr_lines"] == ["HYDRO ONE", "Due 96.40"]
    async with sessionmaker_() as session:
        assert (await session.scalars(select(Receipt))).first() is not None
        assert "from your email" in (await session.scalars(select(Activity.text))).first()


async def test_your_own_address_needs_the_server_to_vouch(sessionmaker_, test_user):
    await _user(sessionmaker_, email_verified=True)
    html = (
        "<table><tr><td>Trip fare</td><td>$21.40</td></tr>"
        "<tr><td>Total</td><td>$23.40</td></tr></table>"
    )
    spoofed = mail("receipts@dataeaver.ca", test_user.email, html=html)
    async with sessionmaker_() as session:
        assert await inbox.handle(session, spoofed, Capturing()) == "no account"

    extractor = Capturing()
    real = mail(
        "receipts@dataeaver.ca",
        test_user.email,
        html=html,
        auth="mx.hostinger.com; dkim=pass header.d=example.com; spf=pass smtp.mailfrom=example.com",
    )
    async with sessionmaker_() as session:
        assert await inbox.handle(session, real, extractor) == "added"
    call = extractor.calls[0]
    assert call["image_bytes"] == b""  # no attachment: the email's text is read
    assert "Subject: Your Uber receipt" in call["ocr_lines"]
    assert "Total $23.40" in call["ocr_lines"]


async def test_me_shows_the_addresses_when_forwarding_is_on(client, monkeypatch):
    assert (await client.get("/v1/auth/me")).json()["receipts_email"] is None
    monkeypatch.setattr(get_settings(), "imap_password", "x")
    me = (await client.get("/v1/auth/me")).json()
    assert me["receipts_email"] == "receipts@dataeaver.ca"
    assert me["receipts_personal_email"].startswith("receipts+")
