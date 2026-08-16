"""sync tables

Revision ID: 0002_sync_tables
Revises: 0001_initial
Create Date: 2026-08-09

Additive only, and never edited once shipped (§11.4, plan §4).
"""

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision = "0002_sync_tables"
down_revision = "0001_initial"
branch_labels = None
depends_on = None

_ID = sa.String(length=36)


def _sync_columns():
    return [
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("device_id", _ID, nullable=False),
        sa.Column("server_seq", sa.BigInteger(), nullable=False),
    ]


IMMUTABLE_FN = """
CREATE OR REPLACE FUNCTION reviews_immutable() RETURNS trigger AS $fn$
BEGIN
  RAISE EXCEPTION 'append-only table (spec section 3): % is not allowed', TG_OP;
END;
$fn$ LANGUAGE plpgsql;
"""


def upgrade() -> None:
    op.create_table(
        "user_sync_state",
        sa.Column("user_id", _ID, sa.ForeignKey("users.id"), primary_key=True),
        sa.Column("last_seq", sa.BigInteger(), nullable=False, server_default="0"),
    )

    op.create_table(
        "devices",
        sa.Column("id", _ID, primary_key=True),
        sa.Column("user_id", _ID, sa.ForeignKey("users.id"), nullable=True),
        sa.Column("platform", sa.String(length=20), nullable=False),
        sa.Column("attested", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
    )

    op.create_table(
        "decks",
        sa.Column("id", _ID, primary_key=True),
        sa.Column("user_id", _ID, sa.ForeignKey("users.id"), nullable=False),
        sa.Column("parent_id", _ID, nullable=True),
        sa.Column("name", sa.String(length=200), nullable=False),
        sa.Column("description", sa.Text(), nullable=True),
        sa.Column("version", sa.Integer(), nullable=False, server_default="1"),
        sa.Column("author", sa.String(length=200), nullable=True),
        sa.Column("license", sa.String(length=100), nullable=True),
        sa.Column("origin", sa.String(length=20), nullable=False, server_default="own"),
        sa.Column("source_deck_id", _ID, nullable=True),
        sa.Column("archived_at", sa.DateTime(timezone=True), nullable=True),
        *_sync_columns(),
    )
    op.create_index("ix_decks_user_seq", "decks", ["user_id", "server_seq"])

    op.create_table(
        "cards",
        sa.Column("id", _ID, primary_key=True),
        sa.Column("user_id", _ID, sa.ForeignKey("users.id"), nullable=False),
        sa.Column("deck_id", _ID, nullable=False),
        sa.Column("front", sa.Text(), nullable=False),
        sa.Column("back", sa.Text(), nullable=False),
        sa.Column("tags", postgresql.JSONB(), nullable=False, server_default="[]"),
        *_sync_columns(),
    )
    op.create_index("ix_cards_user_seq", "cards", ["user_id", "server_seq"])
    op.create_index("ix_cards_deck", "cards", ["deck_id"])

    op.create_table(
        "card_flags",
        sa.Column("card_id", _ID, primary_key=True),
        sa.Column("user_id", _ID, sa.ForeignKey("users.id"), nullable=False),
        sa.Column("status", sa.String(length=20), nullable=False, server_default="active"),
        sa.Column("buried_until", sa.DateTime(timezone=True), nullable=True),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("device_id", _ID, nullable=False),
        sa.Column("server_seq", sa.BigInteger(), nullable=False),
    )
    op.create_index("ix_card_flags_user_seq", "card_flags", ["user_id", "server_seq"])

    op.create_table(
        "reviews",
        sa.Column("id", _ID, primary_key=True),
        sa.Column("user_id", _ID, sa.ForeignKey("users.id"), nullable=False),
        sa.Column("card_id", _ID, nullable=False),
        sa.Column("reviewed_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("grade", sa.SmallInteger(), nullable=False),
        sa.Column("source", sa.String(length=20), nullable=False),
        sa.Column("elapsed_ms", sa.Integer(), nullable=True),
        sa.Column("device_id", _ID, nullable=False),
        sa.Column("server_seq", sa.BigInteger(), nullable=False),
        sa.Column("interval_days_after", sa.Integer(), nullable=True),
        sa.Column("stability_after", sa.Float(), nullable=True),
        sa.Column("difficulty_after", sa.Float(), nullable=True),
        sa.Column("scheduler_version", sa.Integer(), nullable=True),
        sa.Column("app_version", sa.String(length=40), nullable=True),
    )
    op.create_index("ix_reviews_user_seq", "reviews", ["user_id", "server_seq"])
    op.create_index("ix_reviews_card", "reviews", ["card_id", "reviewed_at", "id"])
    op.create_index("ix_reviews_user_reviewed", "reviews", ["user_id", "reviewed_at"])

    op.create_table(
        "progress_resets",
        sa.Column("id", _ID, primary_key=True),
        sa.Column("user_id", _ID, sa.ForeignKey("users.id"), nullable=False),
        sa.Column("card_id", _ID, nullable=False),
        sa.Column("reset_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("device_id", _ID, nullable=False),
        sa.Column("server_seq", sa.BigInteger(), nullable=False),
    )
    op.create_index("ix_progress_resets_user_seq", "progress_resets", ["user_id", "server_seq"])

    op.create_table(
        "goal_history",
        sa.Column("id", _ID, primary_key=True),
        sa.Column("user_id", _ID, sa.ForeignKey("users.id"), nullable=False),
        sa.Column("effective_from_local_date", sa.Date(), nullable=False),
        sa.Column("daily_goal", sa.Integer(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("device_id", _ID, nullable=False),
        sa.Column("server_seq", sa.BigInteger(), nullable=False),
    )
    op.create_index("ix_goal_history_user_seq", "goal_history", ["user_id", "server_seq"])

    op.create_table(
        "user_settings",
        sa.Column("user_id", _ID, sa.ForeignKey("users.id"), primary_key=True),
        sa.Column("key", sa.String(length=60), primary_key=True),
        sa.Column("value", sa.Text(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("device_id", _ID, nullable=False),
        sa.Column("server_seq", sa.BigInteger(), nullable=False),
    )
    op.create_index("ix_user_settings_user_seq", "user_settings", ["user_id", "server_seq"])

    # Section 5.2 — immutability enforced by the database, not by convention.
    # Privilege revocation is the cheaper first line, applied to the
    # application role at deploy; the trigger makes a mistake through a
    # privileged role fail loudly instead of succeeding.
    op.execute(IMMUTABLE_FN)
    op.execute(
        "CREATE TRIGGER reviews_no_update_delete "
        "BEFORE UPDATE OR DELETE ON reviews "
        "FOR EACH ROW EXECUTE FUNCTION reviews_immutable()"
    )
    op.execute(
        "CREATE TRIGGER progress_resets_no_update_delete "
        "BEFORE UPDATE OR DELETE ON progress_resets "
        "FOR EACH ROW EXECUTE FUNCTION reviews_immutable()"
    )


def downgrade() -> None:
    op.execute("DROP TRIGGER IF EXISTS progress_resets_no_update_delete ON progress_resets")
    op.execute("DROP TRIGGER IF EXISTS reviews_no_update_delete ON reviews")
    op.execute("DROP FUNCTION IF EXISTS reviews_immutable()")
    for table in (
        "user_settings",
        "goal_history",
        "progress_resets",
        "reviews",
        "card_flags",
        "cards",
        "decks",
        "devices",
        "user_sync_state",
    ):
        op.drop_table(table)
