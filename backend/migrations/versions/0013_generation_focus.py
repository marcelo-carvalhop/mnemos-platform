"""what the person wants from a PDF or photo, and which pages

Revision ID: 0013_generation_focus
Revises: 0012_email_verification
"""

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision = "0013_generation_focus"
down_revision = "0012_email_verification"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # The instruction the briefing produced (and the person may have edited).
    op.add_column("generation_jobs", sa.Column("focus", sa.Text(), nullable=True))
    # [[from, to], ...], 1-based and inclusive; null means the whole document.
    op.add_column("generation_jobs", sa.Column("page_ranges", postgresql.JSONB(), nullable=True))


def downgrade() -> None:
    op.drop_column("generation_jobs", "page_ranges")
    op.drop_column("generation_jobs", "focus")
