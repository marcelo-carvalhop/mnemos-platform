"""auth: password hash and refresh tokens

Revision ID: 0004_auth
Revises: 0003_quota
Create Date: 2026-08-09
"""

import sqlalchemy as sa
from alembic import op

revision = "0004_auth"
down_revision = "0003_quota"
branch_labels = None
depends_on = None

_ID = sa.String(length=36)


def upgrade() -> None:
    # Nullable, because the anonymous period creates a real user with no
    # credentials (§8.1). Additive, per §11.4.
    op.add_column("users", sa.Column("password_hash", sa.String(length=255), nullable=True))

    op.create_table(
        "refresh_tokens",
        sa.Column("id", sa.String(length=64), primary_key=True),
        sa.Column("user_id", _ID, sa.ForeignKey("users.id"), nullable=False),
        sa.Column("device_id", _ID, nullable=False),
        sa.Column("family_id", sa.String(length=64), nullable=False),
        sa.Column("token_hash", sa.String(length=64), nullable=False, unique=True),
        sa.Column("issued_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("used_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("revoked", sa.Boolean(), nullable=False, server_default=sa.false()),
    )
    op.create_index("ix_refresh_tokens_family", "refresh_tokens", ["family_id"])


def downgrade() -> None:
    op.drop_table("refresh_tokens")
    op.drop_column("users", "password_hash")
