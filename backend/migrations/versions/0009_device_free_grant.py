"""a device remembers that its free generation was spent

Revision ID: 0009_device_free_grant
Revises: 0008_attestation
Create Date: 2026-08-10

§8.4 lets an account be deleted; §8.1 exists because a reinstall must not mint
a second free generation. Deleting the account and registering again is the
same attack with an extra step, so the device row outlives the user carrying
one boolean — no name, no email, no study data.
"""

import sqlalchemy as sa
from alembic import op

revision = "0009_device_free_grant"
down_revision = "0008_attestation"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "devices",
        sa.Column(
            "free_grant_spent",
            sa.Boolean(),
            nullable=False,
            server_default=sa.false(),
        ),
    )


def downgrade() -> None:
    op.drop_column("devices", "free_grant_spent")
