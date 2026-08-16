"""quota usage and reservations

Revision ID: 0003_quota
Revises: 0002_sync_tables
Create Date: 2026-08-09
"""

import sqlalchemy as sa
from alembic import op

revision = "0003_quota"
down_revision = "0002_sync_tables"
branch_labels = None
depends_on = None

_ID = sa.String(length=36)


def upgrade() -> None:
    op.create_table(
        "quota_usage",
        sa.Column("user_id", _ID, sa.ForeignKey("users.id"), primary_key=True),
        # 'lifetime' for the free tier, 'YYYY-MM' for paid plans (§7.7.1).
        sa.Column("period_key", sa.String(length=20), primary_key=True),
        sa.Column("used", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("reserved", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("limit_count", sa.Integer(), nullable=False),
        sa.CheckConstraint("used >= 0 AND reserved >= 0", name="ck_quota_non_negative"),
    )

    op.create_table(
        "quota_reservations",
        sa.Column("id", _ID, primary_key=True),
        sa.Column("user_id", _ID, sa.ForeignKey("users.id"), nullable=False),
        sa.Column("period_key", sa.String(length=20), nullable=False),
        sa.Column("amount", sa.Integer(), nullable=False, server_default="1"),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("committed", sa.Boolean(), nullable=False, server_default=sa.false()),
    )
    op.create_index(
        "ix_quota_reservations_user",
        "quota_reservations",
        ["user_id", "committed", "expires_at"],
    )


def downgrade() -> None:
    op.drop_table("quota_reservations")
    op.drop_table("quota_usage")
