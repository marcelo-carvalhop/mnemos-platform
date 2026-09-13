"""terminal desired/actual state and connectivity telemetry

Revision ID: 0011_terminal_desired_state
Revises: 0010_terminal_credentials
"""

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision = "0011_terminal_desired_state"
down_revision = "0010_terminal_credentials"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "terminal_credentials",
        sa.Column(
            "reported_deck_ids",
            postgresql.JSONB(),
            nullable=False,
            server_default=sa.text("'[]'::jsonb"),
        ),
    )
    op.add_column(
        "terminal_credentials",
        sa.Column("card_count", sa.Integer(), nullable=False, server_default="0"),
    )
    op.add_column(
        "terminal_credentials",
        sa.Column("max_cards", sa.Integer(), nullable=False, server_default="0"),
    )
    op.add_column(
        "terminal_credentials",
        sa.Column("connectivity", sa.String(length=24), nullable=True),
    )
    op.add_column(
        "terminal_credentials",
        sa.Column("wifi_ssid", sa.String(length=32), nullable=True),
    )
    op.add_column(
        "terminal_credentials",
        sa.Column("library_revision", sa.BigInteger(), nullable=False, server_default="0"),
    )
    op.add_column(
        "terminal_credentials",
        sa.Column("last_sync_at", sa.DateTime(timezone=True), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("terminal_credentials", "last_sync_at")
    op.drop_column("terminal_credentials", "library_revision")
    op.drop_column("terminal_credentials", "wifi_ssid")
    op.drop_column("terminal_credentials", "connectivity")
    op.drop_column("terminal_credentials", "max_cards")
    op.drop_column("terminal_credentials", "card_count")
    op.drop_column("terminal_credentials", "reported_deck_ids")
