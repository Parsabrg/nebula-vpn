"""Devices: platform "ios", for subscription links.

Revision ID: 20261111_0022
Revises: 20261104_0021
Create Date: 2026-11-11
"""

from alembic import op

revision = "20261111_0022"
down_revision = "20261104_0021"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.drop_constraint(op.f("ck_devices_device_platform"), "devices", type_="check")
    op.create_check_constraint(
        op.f("ck_devices_device_platform"),
        "devices",
        "platform IN ('android', 'windows', 'ios')",
    )


def downgrade() -> None:
    op.execute("UPDATE devices SET platform = 'android' WHERE platform = 'ios'")
    op.drop_constraint(op.f("ck_devices_device_platform"), "devices", type_="check")
    op.create_check_constraint(
        op.f("ck_devices_device_platform"),
        "devices",
        "platform IN ('android', 'windows')",
    )
