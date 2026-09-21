from collections.abc import AsyncGenerator

from sqlalchemy.ext.asyncio import (
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)

from app.core.config import get_settings

settings = get_settings()

engine = (
    create_async_engine(
        settings.database_url,
        pool_pre_ping=True,
    )
    if settings.database_url
    else None
)

async_session_maker = (
    async_sessionmaker(
        bind=engine,
        class_=AsyncSession,
        expire_on_commit=False,
        autoflush=False,
    )
    if engine
    else None
)

AsyncSessionLocal = async_session_maker


async def get_db() -> AsyncGenerator[AsyncSession, None]:
    if async_session_maker is None:
        raise RuntimeError("DATABASE_URL must be configured before using the database")
    async with async_session_maker() as session:
        try:
            yield session
        finally:
            await session.close()
