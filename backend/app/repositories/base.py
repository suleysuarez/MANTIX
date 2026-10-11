"""Generic repository: the single place for shared persistence helpers.

Concrete repositories subclass `BaseRepository[Model]` and add the queries
specific to their aggregate. Services never build SQL; they call repository
methods. Transaction control (`commit`/`rollback`) lives here so every
repository exposes the same unit-of-work surface.
"""

from collections.abc import Callable, Mapping, Sequence
from dataclasses import dataclass
from typing import Any, ClassVar, Generic, TypeVar

from sqlalchemy import Select, func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm.attributes import InstrumentedAttribute

from app.db.base import Base

ModelT = TypeVar("ModelT", bound=Base)
ItemT = TypeVar("ItemT")
MappedT = TypeVar("MappedT")

MAX_PAGE_SIZE = 500


@dataclass(frozen=True, slots=True)
class Page(Generic[ItemT]):
    """One page of results plus the total number of matching rows."""

    items: list[ItemT]
    total: int
    page: int
    size: int

    def map(self, convert: Callable[[ItemT], MappedT]) -> "Page[MappedT]":
        """Same page metadata with each item converted (e.g. to a schema)."""
        return Page(
            items=[convert(item) for item in self.items],
            total=self.total,
            page=self.page,
            size=self.size,
        )

    @property
    def pages(self) -> int:
        return (self.total + self.size - 1) // self.size if self.size else 0


def escape_like(term: str) -> str:
    """Treat user-typed wildcards (`%`, `_`) as literal text in LIKE/ILIKE."""
    return term.strip().replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")


class BaseRepository(Generic[ModelT]):
    model: ClassVar[type[Base]]

    def __init__(self, session: AsyncSession):
        self.session = session

    # -- Single-entity helpers ------------------------------------------

    async def get(self, entity_id: int) -> ModelT | None:
        result = await self.session.execute(
            select(self.model).where(self.model.id == entity_id)  # type: ignore[attr-defined]
        )
        return result.scalar_one_or_none()

    def add(self, entity: ModelT) -> ModelT:
        self.session.add(entity)
        return entity

    async def add_and_flush(self, entity: ModelT) -> ModelT:
        self.session.add(entity)
        await self.session.flush()
        return entity

    async def delete(self, entity: ModelT) -> None:
        await self.session.delete(entity)
        await self.session.flush()

    async def update_fields(self, entity: ModelT, values: Mapping[str, Any]) -> ModelT:
        for field, value in values.items():
            setattr(entity, field, value)
        await self.session.flush()
        return entity

    # -- Query helpers (listing, search, ordering, pagination) -------------

    @staticmethod
    def apply_search(
        query: Select[Any],
        term: str | None,
        columns: Sequence[InstrumentedAttribute[Any]],
    ) -> Select[Any]:
        if not term or not term.strip() or not columns:
            return query
        pattern = f"%{escape_like(term)}%"
        return query.where(or_(*(col.ilike(pattern, escape="\\") for col in columns)))

    @staticmethod
    def apply_ordering(
        query: Select[Any],
        sort: str | None,
        allowed: Mapping[str, Any],
        default: Sequence[Any] = (),
    ) -> Select[Any]:
        """Order by `sort` (`field` or `-field`); unknown fields are ignored.

        Only whitelisted columns can be sorted on, so the value never reaches SQL.
        `default` is always appended, so it also acts as the tiebreaker that keeps
        pages stable when the requested column has repeated values.
        """
        clauses: list[Any] = []
        if sort:
            descending = sort.startswith("-")
            column = allowed.get(sort.lstrip("-+"))
            if column is not None:
                clauses.append(column.desc() if descending else column.asc())
        clauses.extend(default)
        return query.order_by(*clauses)

    async def paginate(
        self,
        query: Select[Any],
        *,
        page: int = 1,
        size: int = 20,
        offset: int | None = None,
        unique: bool = False,
    ) -> Page[Any]:
        size = min(max(size, 1), MAX_PAGE_SIZE)
        if offset is not None:
            offset = max(offset, 0)
            page = offset // size + 1
        else:
            page = max(page, 1)
            offset = (page - 1) * size
        count_query = select(func.count()).select_from(query.order_by(None).subquery())
        total = int((await self.session.execute(count_query)).scalar_one())
        result = await self.session.execute(query.limit(size).offset(offset))
        scalars = result.unique().scalars() if unique else result.scalars()
        return Page(items=list(scalars.all()), total=total, page=page, size=size)

    # -- Unit of work ---------------------------------------------------

    async def flush(self) -> None:
        await self.session.flush()

    async def commit(self) -> None:
        await self.session.commit()

    async def rollback(self) -> None:
        await self.session.rollback()
