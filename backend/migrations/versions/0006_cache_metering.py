"""record cache tokens separately from input tokens

Revision ID: 0006_cache_metering
Revises: 0005_generation
Create Date: 2026-08-09

The first real generation reported 54 input tokens against a system prompt of
several hundred: the cacheable prefix (§7.4) was read from cache, and cache
reads are counted in their own field, not in `input_tokens`. Storing only
`tokens_in` therefore understates what a job consumed by whatever the cache
served, and §7 is explicit that repricing must not be guesswork. Cache reads
bill at 0.1x and cache writes at 1.25x, so the three figures are not
interchangeable.
"""

import sqlalchemy as sa
from alembic import op

revision = "0006_cache_metering"
down_revision = "0005_generation"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "generation_jobs",
        sa.Column("cache_read_tokens", sa.Integer(), nullable=True),
    )
    op.add_column(
        "generation_jobs",
        sa.Column("cache_write_tokens", sa.Integer(), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("generation_jobs", "cache_write_tokens")
    op.drop_column("generation_jobs", "cache_read_tokens")
