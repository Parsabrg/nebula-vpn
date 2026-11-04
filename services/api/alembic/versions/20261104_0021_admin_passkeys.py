"""Admin passkeys: WebAuthn credentials to sign in with, beside TOTP.

Revision ID: 20261104_0021
Revises: 20261103_0020
Create Date: 2026-11-04
"""

import sqlalchemy as sa

from alembic import op

revision = "20261104_0021"
down_revision = "20261103_0020"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "admin_passkeys",
        sa.Column("admin_user_id", sa.UUID(), nullable=False),
        sa.Column("credential_id", sa.LargeBinary(length=1023), nullable=False),
        sa.Column("public_key", sa.LargeBinary(), nullable=False),
        sa.Column("sign_count", sa.BigInteger(), nullable=False),
        sa.Column("name", sa.String(length=64), nullable=False),
        sa.Column("last_used_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("id", sa.UUID(), nullable=False),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False
        ),
        sa.Column(
            "updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False
        ),
        sa.CheckConstraint(
            "char_length(name) BETWEEN 1 AND 64", name=op.f("ck_admin_passkeys_name_length")
        ),
        sa.CheckConstraint(
            "sign_count >= 0", name=op.f("ck_admin_passkeys_sign_count_not_negative")
        ),
        sa.ForeignKeyConstraint(
            ["admin_user_id"],
            ["admin_users.id"],
            name=op.f("fk_admin_passkeys_admin_user_id_admin_users"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_admin_passkeys")),
        sa.UniqueConstraint("credential_id", name="uq_admin_passkeys_credential_id"),
    )
    op.create_index("ix_admin_passkeys_admin_user_id", "admin_passkeys", ["admin_user_id"])


def downgrade() -> None:
    op.drop_index("ix_admin_passkeys_admin_user_id", table_name="admin_passkeys")
    op.drop_table("admin_passkeys")
