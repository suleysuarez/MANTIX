"""Merge the existing schema and mobile authentication migration heads.

Revision ID: f6c7d8e9a0b1
Revises: e0f1a2b3c4d5, f5b6c7d8e9a0
Create Date: 2026-11-05
"""

from typing import Sequence, Union

revision: str = "f6c7d8e9a0b1"
down_revision: Union[str, Sequence[str], None] = (
    "e0f1a2b3c4d5",
    "f5b6c7d8e9a0",
)
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
