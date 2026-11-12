"""Relays added in the admin panel.

Revision ID: 20261112_0023
Revises: 20261111_0022
Create Date: 2026-11-12
"""

import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

from alembic import op

revision = "20261112_0023"
down_revision = "20261111_0022"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "relay_routes",
        sa.Column("code", sa.String(length=64), nullable=False),
        sa.Column("display_name", sa.String(length=96), nullable=False),
        sa.Column("exit_server_id", sa.UUID(), nullable=False),
        sa.Column("via_server_id", sa.UUID(), nullable=False),
        sa.Column("host", sa.String(length=253), nullable=False),
        sa.Column("ports", postgresql.JSONB(astext_type=sa.Text()), nullable=False),
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
            "length(code) BETWEEN 1 AND 64", name=op.f("ck_relay_routes_code_length")
        ),
        sa.CheckConstraint(
            "length(display_name) BETWEEN 1 AND 96",
            name=op.f("ck_relay_routes_display_name_length"),
        ),
        sa.CheckConstraint(
            "length(host) BETWEEN 1 AND 253 AND host !~ '[/@[:space:]]'",
            name=op.f("ck_relay_routes_host_format"),
        ),
        sa.CheckConstraint(
            "exit_server_id <> via_server_id", name=op.f("ck_relay_routes_exit_is_not_via")
        ),
        sa.ForeignKeyConstraint(
            ["exit_server_id"],
            ["vpn_servers.id"],
            name=op.f("fk_relay_routes_exit_server_id_vpn_servers"),
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["via_server_id"],
            ["vpn_servers.id"],
            name=op.f("fk_relay_routes_via_server_id_vpn_servers"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_relay_routes")),
        sa.UniqueConstraint("code", name="uq_relay_routes_code"),
    )


def downgrade() -> None:
    op.drop_table("relay_routes")
