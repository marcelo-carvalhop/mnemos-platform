"""invites as rows, and the invite each account signed up with

Revision ID: 0015_invites
Revises: 0014_waitlist
"""

import sqlalchemy as sa
from alembic import op

revision = "0015_invites"
down_revision = "0014_waitlist"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "invites",
        sa.Column("id", sa.String(36), primary_key=True),
        sa.Column("code_hash", sa.String(64), nullable=False, unique=True),
        sa.Column("code_hint", sa.String(8), nullable=False),
        sa.Column("label", sa.String(120), nullable=False),
        sa.Column("max_uses", sa.Integer(), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.func.now(),
        ),
        sa.Column("revoked_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.add_column(
        "users",
        sa.Column("invite_id", sa.String(36), sa.ForeignKey("invites.id"), nullable=True),
    )
    op.create_index("ix_users_invite_id", "users", ["invite_id"])


def downgrade() -> None:
    op.drop_index("ix_users_invite_id", table_name="users")
    op.drop_column("users", "invite_id")
    op.drop_table("invites")
