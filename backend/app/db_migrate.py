"""Bring the database up to the current Alembic revision on startup.

Handles three cases:

* **Fresh DB** — no tables: create them from the ORM metadata, then stamp head.
* **Bootstrapped DB** — tables were made by ``Base.metadata.create_all`` in an
  earlier build and there's no ``alembic_version``: repair the one table that
  pre-dates a migration (``users``, from before the Auth0 switch), then stamp head.
* **Migrated DB** — ``alembic_version`` exists: just ``upgrade head``.

Called from the app lifespan (guarded by ``AUTO_CREATE_TABLES``). Alembic's
command API spins its own event loop via ``env.py``, so it runs in a worker
thread.
"""

import asyncio
import logging
from pathlib import Path

from alembic.config import Config
from alembic.runtime.migration import MigrationContext
from sqlalchemy import text

from alembic import command
from app.db import engine
from app.models import Base

logger = logging.getLogger(__name__)

_ALEMBIC_INI = Path(__file__).resolve().parent.parent / "alembic.ini"

# Migration 0002's changes, expressed idempotently for a `users` table that was
# created by create_all() before Auth0 (hashed_password, no auth0_sub).
_USERS_REPAIR = (
    "ALTER TABLE users ADD COLUMN IF NOT EXISTS auth0_sub VARCHAR(255)",
    "CREATE UNIQUE INDEX IF NOT EXISTS ix_users_auth0_sub ON users (auth0_sub)",
    "ALTER TABLE users DROP COLUMN IF EXISTS hashed_password",
)


def _current_revision(sync_conn) -> str | None:
    return MigrationContext.configure(sync_conn).get_current_revision()


async def bootstrap_schema() -> None:
    async with engine.begin() as conn:
        current = await conn.run_sync(_current_revision)

        if current is None:
            await conn.run_sync(Base.metadata.create_all)
            if conn.dialect.name == "postgresql":
                has_users = await conn.scalar(text("SELECT to_regclass('public.users')"))
                if has_users:
                    for stmt in _USERS_REPAIR:
                        await conn.exec_driver_sql(stmt)

    cfg = Config(str(_ALEMBIC_INI))
    if current is None:
        await asyncio.to_thread(command.stamp, cfg, "head")
        logger.info("DB bootstrapped from models; Alembic stamped to head.")
    else:
        await asyncio.to_thread(command.upgrade, cfg, "head")
        logger.info("Alembic upgraded to head (was at %s).", current)
