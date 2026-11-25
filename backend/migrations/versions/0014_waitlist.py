"""who asked to hear when the AI plan opens

Revision ID: 0014_waitlist
Revises: 0013_generation_focus
"""

import sqlalchemy as sa
from alembic import op

revision = "0014_waitlist"
down_revision = "0013_generation_focus"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "waitlist",
        sa.Column("email", sa.String(320), primary_key=True),
        sa.Column("plan", sa.String(20), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.func.now(),
        ),
    )


def downgrade() -> None:
    op.drop_table("waitlist")
