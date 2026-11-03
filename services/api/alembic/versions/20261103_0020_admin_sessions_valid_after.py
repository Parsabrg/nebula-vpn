"""Admin sessions valid after: changing a password signs out other sessions.

Revision ID: 20261103_0020
Revises: 20261030_0019
Create Date: 2026-11-03

Admin sessions live in Redis with no index by admin, so they cannot be
listed to revoke. The admin row, which every request reads, says instead
from when its sessions count: older ones are refused.
"""

import sqlalchemy as sa

from alembic import op

revision = "20261103_0020"
down_revision = "20261030_0019"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "admin_users",
        sa.Column("sessions_valid_after", sa.DateTime(timezone=True), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("admin_users", "sessions_valid_after")
