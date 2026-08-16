"""single-use attestation challenges, and the iOS key id

Revision ID: 0008_attestation
Revises: 0007_error_code_values
Create Date: 2026-08-09

§8.1 was a presence check — `attestation is not None` — which is not a weak
check but the absence of one. A challenge makes the assertion unreplayable and
the key id stops one App Attest key registering two installs.
"""

import sqlalchemy as sa
from alembic import op

revision = "0008_attestation"
down_revision = "0007_error_code_values"
branch_labels = None
depends_on = None

_ID = sa.String(length=36)


def upgrade() -> None:
    op.create_table(
        "attestation_challenges",
        sa.Column("nonce", sa.String(length=64), primary_key=True),
        sa.Column("device_id", _ID, nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
    )
    # Expired rows are swept on issue; the index keeps that sweep cheap.
    op.create_index(
        "ix_attestation_challenges_expires_at", "attestation_challenges", ["expires_at"]
    )
    op.add_column("devices", sa.Column("attest_key_id", sa.String(length=64), nullable=True))
    op.create_unique_constraint("uq_devices_attest_key_id", "devices", ["attest_key_id"])


def downgrade() -> None:
    op.drop_constraint("uq_devices_attest_key_id", "devices", type_="unique")
    op.drop_column("devices", "attest_key_id")
    op.drop_index("ix_attestation_challenges_expires_at", table_name="attestation_challenges")
    op.drop_table("attestation_challenges")
