#!/usr/bin/env python3
"""Seed a few sample expenses across the current + last 3 months, so the
dashboard / trend / month views have something to show.

Every seeded expense's merchant starts with "Seed · " so it's easy to spot and
remove (`--clean`).

Usage:
    # 1. Grab an access token while signed in to the web app:
    #      open https://<your-web-host>/auth/access-token   (copy "access_token")
    # 2. Run:
    AI_RECEIPT_TOKEN=<token> python3 scripts/seed_expenses.py
    AI_RECEIPT_TOKEN=<token> python3 scripts/seed_expenses.py --clean

Options:
    --api URL     API base (default: $AI_RECEIPT_API or the dev host)
    --token TOK   Access token (default: $AI_RECEIPT_TOKEN)
    --clean       Delete previously seeded expenses instead of creating.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.request
from datetime import date

DEFAULT_API = (
    "https://ai-receipt-dev-api.ashymoss-2c5773fb.eastus2.azurecontainerapps.io"
)
SEED_PREFIX = "Seed · "  # "Seed · "

# months back -> list of (merchant, category, total). Roughly descending totals
# so the trend chart tells a story.
PLAN: dict[int, list[tuple[str, str, str]]] = {
    3: [
        ("Costco", "groceries", "640.00"),
        ("United Airlines", "travel", "980.00"),
        ("Chevron", "transport", "210.00"),
    ],
    2: [
        ("Safeway", "groceries", "430.00"),
        ("Apple Store", "shopping", "780.00"),
        ("Lyft", "transport", "140.00"),
    ],
    1: [
        ("Trader Joe's", "groceries", "380.00"),
        ("Corner Cafe", "restaurants", "190.00"),
        ("PG&E", "utilities", "180.00"),
    ],
    0: [
        ("Trader Joe's", "groceries", "210.00"),
        ("Coffee Bar", "restaurants", "55.00"),
    ],
}


def _month_day(months_back: int, day: int = 12) -> str:
    today = date.today()
    if months_back == 0:
        day = min(day, today.day)  # never future-dated
    m = today.month - 1 - months_back
    y = today.year + m // 12
    m = m % 12 + 1
    return f"{y:04d}-{m:02d}-{day:02d}"


def _request(method: str, url: str, token: str, body: dict | None = None) -> tuple[int, bytes]:
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", f"Bearer {token}")
    if data is not None:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req) as resp:
            return resp.status, resp.read()
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read()


def create(api: str, token: str) -> None:
    made = 0
    for months_back, rows in sorted(PLAN.items(), reverse=True):
        for merchant, category, total in rows:
            body = {
                "merchant": f"{SEED_PREFIX}{merchant}",
                "date": _month_day(months_back),
                "total": total,
                "tax": "0",
                "category": category,
                "currency": "USD",
                "items": [],
            }
            status, raw = _request("POST", f"{api}/v1/receipts", token, body)
            if status == 201:
                made += 1
                print(f"  + {body['date']}  {merchant:<18} {category:<12} ${total}")
            else:
                print(f"  ! failed ({status}) for {merchant}: {raw.decode()[:200]}", file=sys.stderr)
    print(f"\nCreated {made} seeded expenses.")


def clean(api: str, token: str) -> None:
    status, raw = _request("GET", f"{api}/v1/receipts?limit=200", token)
    if status != 200:
        sys.exit(f"list failed ({status}): {raw.decode()[:200]}")
    receipts = json.loads(raw)
    targets = [r for r in receipts if r.get("merchant", "").startswith(SEED_PREFIX)]
    for r in targets:
        d_status, d_raw = _request("DELETE", f"{api}/v1/receipts/{r['id']}", token)
        mark = "-" if d_status in (200, 204) else "!"
        print(f"  {mark} {r['merchant']}  ({d_status})")
    print(f"\nRemoved {len(targets)} seeded expenses.")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--api", default=os.environ.get("AI_RECEIPT_API", DEFAULT_API))
    parser.add_argument("--token", default=os.environ.get("AI_RECEIPT_TOKEN", ""))
    parser.add_argument("--clean", action="store_true")
    args = parser.parse_args()

    if not args.token:
        sys.exit("Need an access token: set AI_RECEIPT_TOKEN or pass --token.")

    api = args.api.rstrip("/")
    print(f"{'Cleaning' if args.clean else 'Seeding'} {api} ...\n")
    (clean if args.clean else create)(api, args.token)


if __name__ == "__main__":
    main()
