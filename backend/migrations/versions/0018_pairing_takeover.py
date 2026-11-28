"""a terminal that proves its credential can move to the account claiming it

Revision ID: 0018_pairing_takeover
Revises: 0017_terminal_pairings
"""

import sqlalchemy as sa
from alembic import op

revision = "0018_pairing_takeover"
down_revision = "0017_terminal_pairings"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "terminal_pairings",
        sa.Column("takeover_allowed", sa.Boolean(), nullable=False, server_default=sa.false()),
    )


def downgrade() -> None:
    op.drop_column("terminal_pairings", "takeover_allowed")
