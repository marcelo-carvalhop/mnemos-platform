"""when the person saw that a generation failed

Revision ID: 0016_failure_seen
Revises: 0015_invites
"""

import sqlalchemy as sa
from alembic import op

revision = "0016_failure_seen"
down_revision = "0015_invites"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "generation_jobs",
        sa.Column("failure_seen_at", sa.DateTime(timezone=True), nullable=True),
    )
    # Failures older than a day are old news: counting them as unseen would
    # greet everyone with a list of last week's errors. Recent ones stay
    # unseen, so the person who just lost one finds out.
    op.execute(
        "UPDATE generation_jobs SET failure_seen_at = now() "
        "WHERE status = 'failed' AND coalesce(finished_at, created_at) < now() - interval '1 day'"
    )


def downgrade() -> None:
    op.drop_column("generation_jobs", "failure_seen_at")
