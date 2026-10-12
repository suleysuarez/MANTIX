"""Shared fixtures.

Repository tests run against a real PostgreSQL database (JSONB, partial
indexes and `make_interval` are not portable). Point `TEST_DATABASE_URL` at a
*disposable* database; the tests are skipped when it is not set. Each test gets
a fresh schema (create_all/drop_all) and an isolated session.
"""

import os
from collections.abc import AsyncIterator

# Must be set before `app.main` is imported: many tests hammer the API from one IP.
os.environ.setdefault("RATE_LIMIT_PER_MINUTE", "0")

import pytest
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

import app.models  # noqa: F401  (register all tables on Base.metadata)
from app.core.config import Settings
from app.db.base import Base

TEST_DATABASE_URL = os.environ.get("TEST_DATABASE_URL", "")


@pytest.fixture
async def db_session() -> AsyncIterator[AsyncSession]:
    if not TEST_DATABASE_URL:
        pytest.skip("TEST_DATABASE_URL is not set")
    url = Settings(database_url=TEST_DATABASE_URL).database_url
    engine = create_async_engine(url)
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
        await conn.run_sync(Base.metadata.create_all)
    maker = async_sessionmaker(engine, expire_on_commit=False, autoflush=False)
    async with maker() as session:
        yield session
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
    await engine.dispose()
