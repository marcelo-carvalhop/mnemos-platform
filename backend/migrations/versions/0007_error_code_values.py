"""normalise error codes written as "ErrorCode.MEMBER"

Revision ID: 0007_error_code_values
Revises: 0006_cache_metering
Create Date: 2026-08-09

`class ErrorCode(str, Enum)` stringifies as "ErrorCode.TOPIC_TOO_VAGUE" on
Python 3.11+, not as its value, and that string was written to
generation_jobs.error_code. §10 exists so the client maps a code to copy
instead of matching on server prose — a code it cannot map is the same as no
code at all. The enum is now a StrEnum; this repairs what was already stored.
"""

from alembic import op

revision = "0007_error_code_values"
down_revision = "0006_cache_metering"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(
        """
        UPDATE generation_jobs
           SET error_code = lower(split_part(error_code, '.', 2))
         WHERE error_code LIKE 'ErrorCode.%'
        """
    )


def downgrade() -> None:
    # Deliberately not reversible: the old form was a defect, and restoring it
    # would put unmappable codes back in front of clients.
    pass
