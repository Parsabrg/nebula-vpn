"""Import every model so SQLAlchemy and Alembic see the complete schema."""

from nebula_api.models.approval import (
    AccountRequest,
    AccountRequestEvent,
    PasswordResetToken,
    UserActivation,
)
from nebula_api.models.deployment import Deployment
from nebula_api.models.enrollment import NodeEnrollmentToken
from nebula_api.models.identity import (
    AdminMfaRecoveryCode,
    AdminPasskey,
    AdminTotpCredential,
    AdminUser,
    Device,
    RefreshToken,
    User,
    UserSession,
)
from nebula_api.models.operations import (
    AgentOperation,
    AuditLog,
    EmailDelivery,
    ReconciliationRecord,
    ServerHealth,
    Setting,
)
from nebula_api.models.provisioning import (
    DeviceProtocolCredential,
    WireGuardPeer,
    XrayClient,
)
from nebula_api.models.topology import (
    DeploymentChoice,
    Protocol,
    ProtocolProfile,
    ProtocolProfilePlatform,
    RelayRoute,
    ServerProtocolCapability,
    UserProtocolPermission,
    UserServerAssignment,
    VPNServer,
)
from nebula_api.models.usage import CredentialUsage

__all__ = [
    "AccountRequest",
    "AccountRequestEvent",
    "AdminMfaRecoveryCode",
    "AdminPasskey",
    "AdminTotpCredential",
    "AdminUser",
    "AgentOperation",
    "AuditLog",
    "CredentialUsage",
    "Deployment",
    "DeploymentChoice",
    "Device",
    "DeviceProtocolCredential",
    "EmailDelivery",
    "NodeEnrollmentToken",
    "PasswordResetToken",
    "Protocol",
    "ProtocolProfile",
    "ProtocolProfilePlatform",
    "ReconciliationRecord",
    "RefreshToken",
    "RelayRoute",
    "ServerHealth",
    "ServerProtocolCapability",
    "Setting",
    "User",
    "UserActivation",
    "UserProtocolPermission",
    "UserServerAssignment",
    "UserSession",
    "VPNServer",
    "WireGuardPeer",
    "XrayClient",
]
