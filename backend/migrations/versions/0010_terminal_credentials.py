"""terminal scoped credentials

Revision ID: 0010_terminal_credentials
Revises: 0009_device_free_grant
"""

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision = "0010_terminal_credentials"
down_revision = "0009_device_free_grant"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "terminal_credentials",
        sa.Column("device_id", sa.String(length=64), primary_key=True),
        sa.Column("user_id", sa.String(length=36), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("token_hash", sa.String(length=64), nullable=False, unique=True),
        sa.Column("model", sa.String(length=80), nullable=False),
        sa.Column("firmware", sa.String(length=40), nullable=False),
        sa.Column(
            "deck_ids",
            postgresql.JSONB(),
            nullable=False,
            server_default=sa.text("'[]'::jsonb"),
        ),
        sa.Column("revoked", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.Column("last_seen_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.create_index("ix_terminal_credentials_user", "terminal_credentials", ["user_id"])


def downgrade() -> None:
    op.drop_index("ix_terminal_credentials_user", table_name="terminal_credentials")
    op.drop_table("terminal_credentials")
