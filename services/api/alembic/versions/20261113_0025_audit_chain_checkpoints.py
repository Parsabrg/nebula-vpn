"""Audit export chain checkpoints, written when old events are pruned.

Revision ID: 20261113_0025
Revises: 20261113_0024
Create Date: 2026-11-13
"""

import sqlalchemy as sa

from alembic import op

revision = "20261113_0025"
down_revision = "20261113_0024"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "audit_chain_checkpoints",
        sa.Column("until", sa.DateTime(timezone=True), nullable=False),
        sa.Column("event_count", sa.BigInteger(), nullable=False),
        sa.Column("head", sa.String(length=64), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.Column("id", sa.UUID(), nullable=False),
        sa.CheckConstraint(
            "head ~ '^[0-9a-f]{64}$'", name=op.f("ck_audit_chain_checkpoints_head_format")
        ),
        sa.CheckConstraint(
            "event_count > 0", name=op.f("ck_audit_chain_checkpoints_event_count_positive")
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_audit_chain_checkpoints")),
    )
    op.create_index(
        "ix_audit_chain_checkpoints_until", "audit_chain_checkpoints", ["until"], unique=False
    )
    # Append-only for the API, like audit_logs itself.
    op.execute("REVOKE UPDATE, DELETE ON TABLE audit_chain_checkpoints FROM nebula_app_runtime")


def downgrade() -> None:
    op.drop_index("ix_audit_chain_checkpoints_until", table_name="audit_chain_checkpoints")
    op.drop_table("audit_chain_checkpoints")
