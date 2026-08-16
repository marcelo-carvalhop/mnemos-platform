"""generation jobs and the approval queue

Revision ID: 0005_generation
Revises: 0004_auth
Create Date: 2026-08-09
"""

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision = "0005_generation"
down_revision = "0004_auth"
branch_labels = None
depends_on = None

_ID = sa.String(length=36)


def upgrade() -> None:
    op.create_table(
        "generation_jobs",
        sa.Column("id", _ID, primary_key=True),
        sa.Column("user_id", _ID, sa.ForeignKey("users.id"), nullable=False),
        sa.Column("source_type", sa.String(length=20), nullable=False),
        sa.Column("status", sa.String(length=20), nullable=False, server_default="queued"),
        sa.Column("target_deck_id", _ID, nullable=False),
        sa.Column("requested_count", sa.Integer(), nullable=False, server_default="10"),
        sa.Column("level", sa.String(length=20), nullable=False, server_default="intermediario"),
        sa.Column("topic", sa.Text(), nullable=True),
        sa.Column("upload_key", sa.String(length=255), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("started_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("finished_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("error_code", sa.String(length=40), nullable=True),
        sa.Column("error_detail", sa.Text(), nullable=True),
        sa.Column("quota_reservation_id", _ID, nullable=True),
        sa.Column("tokens_in", sa.Integer(), nullable=True),
        sa.Column("tokens_out", sa.Integer(), nullable=True),
        sa.CheckConstraint(
            "status IN ('queued','reading','generating','ready','failed')",
            name="ck_generation_status",
        ),
    )
    # The claim query: oldest queued job first.
    op.create_index("ix_generation_jobs_queue", "generation_jobs", ["status", "created_at"])
    op.create_index("ix_generation_jobs_user", "generation_jobs", ["user_id", "created_at"])

    op.create_table(
        "pending_cards",
        sa.Column("id", _ID, primary_key=True),
        sa.Column("job_id", _ID, sa.ForeignKey("generation_jobs.id"), nullable=False),
        sa.Column("user_id", _ID, sa.ForeignKey("users.id"), nullable=False),
        sa.Column("deck_id", _ID, nullable=False),
        sa.Column("front", sa.Text(), nullable=False),
        sa.Column("back", sa.Text(), nullable=False),
        sa.Column("tags", postgresql.JSONB(), nullable=False, server_default="[]"),
        sa.Column("position", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("decision", sa.String(length=20), nullable=True),
        sa.Column("decided_at", sa.DateTime(timezone=True), nullable=True),
        sa.CheckConstraint(
            "decision IS NULL OR decision IN ('approved','discarded')",
            name="ck_pending_decision",
        ),
    )
    op.create_index("ix_pending_cards_job", "pending_cards", ["job_id", "position"])


def downgrade() -> None:
    op.drop_table("pending_cards")
    op.drop_table("generation_jobs")
