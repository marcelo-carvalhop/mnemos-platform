"""email confirmation for invite-only accounts

Revision ID: 0012_email_verification
Revises: 0011_terminal_desired_state
"""

import sqlalchemy as sa
from alembic import op

revision = "0012_email_verification"
down_revision = "0011_terminal_desired_state"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "users", sa.Column("email_verified_at", sa.DateTime(timezone=True), nullable=True)
    )
    op.add_column(
        "users", sa.Column("email_verification_hash", sa.String(length=64), nullable=True)
    )
    op.add_column(
        "users",
        sa.Column("email_verification_sent_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.create_index(
        "ix_users_email_verification_hash",
        "users",
        ["email_verification_hash"],
        unique=True,
        postgresql_where=sa.text("email_verification_hash IS NOT NULL"),
    )
    # Accounts that already signed in with an email keep working: confirmation
    # did not exist when they were created, so there is nothing to confirm.
    op.execute("UPDATE users SET email_verified_at = now() WHERE email IS NOT NULL")


def downgrade() -> None:
    op.drop_index("ix_users_email_verification_hash", table_name="users")
    op.drop_column("users", "email_verification_sent_at")
    op.drop_column("users", "email_verification_hash")
    op.drop_column("users", "email_verified_at")
