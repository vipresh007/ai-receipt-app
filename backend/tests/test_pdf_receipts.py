"""PDF receipts: rendered to an image and read with their own text (services/pdf.py)."""

import base64

from app.api.deps import get_extractor
from app.main import app
from app.schemas.extraction import ExtractedReceipt


def tiny_pdf(*lines: str) -> bytes:
    """A one-page PDF with real text, built by hand (no PDF library needed)."""
    text = "BT /F1 14 Tf 40 760 Td " + " ".join(f"({line}) Tj 0 -20 Td" for line in lines) + " ET"
    objects = [
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R "
        "/Resources << /Font << /F1 5 0 R >> >> >>",
        f"<< /Length {len(text)} >>\nstream\n{text}\nendstream",
        "<< /Type /Font /Subtype /Type1 /BaseFont /Courier >>",
    ]
    out = b"%PDF-1.4\n"
    offsets = []
    for number, body in enumerate(objects, start=1):
        offsets.append(len(out))
        out += f"{number} 0 obj\n{body}\nendobj\n".encode()
    xref = len(out)
    out += f"xref\n0 {len(objects) + 1}\n0000000000 65535 f \n".encode()
    out += "".join(f"{o:010d} 00000 n \n" for o in offsets).encode()
    out += f"trailer\n<< /Size {len(objects) + 1} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF".encode()
    return out


class Capturing:
    seen: dict = {}

    def extract(self, *, image_bytes: bytes, ocr_lines: list[str], **_):
        Capturing.seen = {"image": image_bytes, "lines": ocr_lines}
        return ExtractedReceipt(
            merchant="Hydro One",
            purchased_at="2026-10-15",
            total="96.40",
            tax="11.09",
            category="utilities",
            currency="CAD",
            line_items=[],
            confidence=0.9,
        )


async def test_a_pdf_is_read_from_its_image_and_text(client):
    app.dependency_overrides[get_extractor] = Capturing
    pdf = tiny_pdf("HYDRO ONE", "Amount due 96.40")
    r = await client.post(
        "/v1/extract",
        json={
            "imageBase64": base64.b64encode(pdf).decode(),
            "ocrLines": [],
            "clientRequestID": "p1",
        },
    )
    assert r.status_code == 200, r.text
    assert r.json()["merchant"] == "Hydro One"
    assert Capturing.seen["image"][:3] == b"\xff\xd8\xff"  # a JPEG, not the PDF
    assert Capturing.seen["lines"] == ["HYDRO ONE", "Amount due 96.40"]


async def test_a_broken_pdf_says_so(client):
    r = await client.post(
        "/v1/extract",
        json={"imageBase64": base64.b64encode(b"%PDF-1.4 nope").decode(), "clientRequestID": "p2"},
    )
    assert r.status_code == 422 and "PDF" in r.json()["detail"]
