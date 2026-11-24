"""DNS tunnels per server, set in the admin panel.

Revision ID: 20261124_0026
Revises: 20261113_0025
Create Date: 2026-11-24
"""

import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

from alembic import op

revision = "20261124_0026"
down_revision = "20261113_0025"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "dns_tunnels",
        sa.Column("vpn_server_id", sa.UUID(), nullable=False),
        sa.Column("domains", postgresql.JSONB(astext_type=sa.Text()), nullable=False),
        sa.Column("key", sa.String(length=32), nullable=False),
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
        sa.CheckConstraint("key ~ '^[0-9a-f]{32}$'", name=op.f("ck_dns_tunnels_key_format")),
        sa.ForeignKeyConstraint(
            ["vpn_server_id"],
            ["vpn_servers.id"],
            name=op.f("fk_dns_tunnels_vpn_server_id_vpn_servers"),
            ondelete="CASCADE",
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_dns_tunnels")),
        sa.UniqueConstraint("vpn_server_id", name="uq_dns_tunnels_vpn_server_id"),
    )


def downgrade() -> None:
    op.drop_table("dns_tunnels")
