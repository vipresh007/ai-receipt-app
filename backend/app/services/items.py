"""Tidy a receipt line as printed into what a person would call it.

"Bananas 4011 1.035 kg @ $1.91/kg" → name "Bananas", detail "1.035 kg @ $1.91/kg"
"Milk Homo 6442000020"            → name "Milk Homo"
"Cilantro 4889 2 @ 1/ $0.99"      → name "Cilantro", detail "2 @ 1/ $0.99"

Product codes (PLU / barcode: a 4–14 digit number on its own) go; the
weight-or-count "@" part moves to `detail`. The server tidies every line
before it's stored (migration 0022 tidied the ones already saved)."""

import re

# From the number before an "@" ("1.035 kg @", "2 @") to the end.
_AT = re.compile(r"\s*(\d+(?:\.\d+)?\s*(?:kg|lb|lbs|g|ea)?\s*@.*)$", re.IGNORECASE)
_CODE = re.compile(r"(?<![\w.$])\d{4,14}(?![\w.%])")


def tidy(name: str, detail: str | None = None) -> tuple[str, str | None]:
    raw = (name or "").strip()
    m = _AT.search(raw)
    if m and m.start() > 0:
        detail = detail or m.group(1).strip()
        raw = raw[: m.start()]
    cleaned = re.sub(r"\s{2,}", " ", _CODE.sub("", raw)).strip(" -·,")
    return (cleaned or raw.strip() or name), (detail or None)


def tidy_line(item: dict) -> dict:
    name, detail = tidy(item.get("name", ""), item.get("detail"))
    out = {**item, "name": name}
    if detail:
        out["detail"] = detail
    return out
