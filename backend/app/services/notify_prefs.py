"""Which notifications someone wants, per kind and channel (Account →
Notifications). Everything still lands in Activity; this only decides what
also goes out as a push or an email. Unset = on."""

from app.models import User

# group → (activity kinds, channels it can use)
GROUPS: dict[str, tuple[set[str], tuple[str, ...]]] = {
    "expenses": (
        {
            "expense_added",
            "expense_edited",
            "expense_deleted",
            "repeated",
            "joined",
            "group_changed",
        },
        ("push", "email"),
    ),
    "comments": ({"comment"}, ("push",)),
    "payments": ({"payment"}, ("push", "email")),
    "reminders": ({"reminder"}, ("push", "email")),  # someone nudging you to pay
    "returns": ({"return_reminder"}, ("push", "email")),
    "emailed": ({"emailed"}, ("push",)),  # receipts you forwarded, added
}

KEYS = [f"{group}.{channel}" for group, (_, channels) in GROUPS.items() for channel in channels]


def group_of(kind: str) -> str | None:
    for group, (kinds, _) in GROUPS.items():
        if kind in kinds:
            return group
    return None


def resolved(user: User) -> dict[str, bool]:
    saved = user.notify_prefs or {}
    return {key: bool(saved.get(key, True)) for key in KEYS}


def allowed(user: User, kind: str, channel: str) -> bool:
    if channel == "email" and not user.email_notifications:
        return False  # the master switch for emails
    group = group_of(kind)
    if group is None:
        return True
    return bool((user.notify_prefs or {}).get(f"{group}.{channel}", True))


def merged(user: User, changes: dict[str, bool]) -> dict[str, bool]:
    prefs = dict(user.notify_prefs or {})
    for key, value in changes.items():
        if key in KEYS:
            prefs[key] = bool(value)
    return prefs
