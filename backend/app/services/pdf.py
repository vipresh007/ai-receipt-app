"""PDF receipts and invoices: turned into what the extractor already reads —
one image (the first pages, stacked) plus the PDF's own text lines, which are
exact where a photo's OCR is a guess."""

import io

import pypdfium2 as pdfium
from PIL import Image

MAX_PAGES = 2  # receipts are one page; invoices put the total on page 2 at most
MAX_TEXT_PAGES = 4
WIDTH = 1240  # px; plenty for the model to read small print


def is_pdf(data: bytes) -> bool:
    return data[:5] == b"%PDF-"


class PdfError(ValueError):
    pass


def to_image_and_text(data: bytes) -> tuple[bytes, list[str]]:
    """(JPEG of the first pages, the text lines of the first few pages)."""
    try:
        doc = pdfium.PdfDocument(data)
    except pdfium.PdfiumError as exc:
        raise PdfError("That PDF couldn't be opened.") from exc
    try:
        if len(doc) == 0:
            raise PdfError("That PDF has no pages.")
        pages: list[Image.Image] = []
        lines: list[str] = []
        for index in range(min(len(doc), MAX_TEXT_PAGES)):
            page = doc[index]
            text = page.get_textpage().get_text_range()
            lines += [line.strip()[:500] for line in text.splitlines() if line.strip()]
            if index < MAX_PAGES:
                scale = WIDTH / max(page.get_width(), 1)
                pages.append(page.render(scale=scale).to_pil().convert("RGB"))
        height = sum(p.height for p in pages)
        sheet = Image.new("RGB", (WIDTH, height), "white")
        y = 0
        for p in pages:
            sheet.paste(p, (0, y))
            y += p.height
        out = io.BytesIO()
        sheet.save(out, format="JPEG", quality=85)
        return out.getvalue(), lines[:400]
    finally:
        doc.close()
