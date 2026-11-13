"""Choices an administrator makes for the whole deployment, by name.

Revision ID: 20261113_0024
Revises: 20261112_0023
Create Date: 2026-11-13
"""

import sqlalchemy as sa

from alembic import op

revision = "20261113_0024"
down_revision = "20261112_0023"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "deployment_choices",
        sa.Column("key", sa.String(length=64), nullable=False),
        sa.Column("value", sa.String(length=260), nullable=False),
        sa.Column("updated_by_admin_id", sa.UUID(), nullable=True),
        sa.Column("id", sa.UUID(), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.CheckConstraint(
            "key IN ('subscription_host')", name=op.f("ck_deployment_choices_key_allowlist")
        ),
        sa.CheckConstraint(
            "value ~ '^[A-Za-z0-9.:-]{1,260}$'", name=op.f("ck_deployment_choices_value_format")
        ),
        sa.ForeignKeyConstraint(
            ["updated_by_admin_id"],
            ["admin_users.id"],
            name=op.f("fk_deployment_choices_updated_by_admin_id_admin_users"),
            ondelete="SET NULL",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_deployment_choices")),
        sa.UniqueConstraint("key", name="uq_deployment_choices_key"),
    )


def downgrade() -> None:
    op.drop_table("deployment_choices")
