"""Minting enrollment tokens, and exchanging one for a node identity.

The exchange is the only place in this system where something with no
identity is handed one, so it is written to fail closed at every step and to
say as little as possible about why.

Uniform failure matters more here than it looks. Anyone can reach this
endpoint -- a node being enrolled has no credentials yet, so it cannot be
behind authentication. If an unknown token answered differently from an
expired one, or from one already redeemed, the endpoint would be an oracle
telling somebody probing with guesses which of them had been real.
"""

import logging
import re
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from ipaddress import IPv4Address, IPv4Network
from uuid import UUID, uuid4

from sqlalchemy import or_, select

from nebula_api.auth.audit import add_audit_event
from nebula_api.auth.opaque_tokens import (
    KeyRing,
    OpaqueTokenError,
    digest_opaque_token,
    issue_opaque_token,
)
from nebula_api.db.engine import SessionFactory
from nebula_api.models.enrollment import NodeEnrollmentToken
from nebula_api.models.topology import ProtocolProfile, ServerProtocolCapability, VPNServer
from nebula_api.models.types import CapabilityState, ServerState
from nebula_api.pki import CertificateAuthority, PkiError, sign_node_certificate

_LOGGER = logging.getLogger(__name__)

# Bounds what the digest is derived over, so a token issued for enrollment
# cannot be presented as a refresh token or a password reset and vice versa.
ENROLLMENT_NAMESPACE = "node-enrollment"

DEFAULT_TOKEN_LIFETIME = timedelta(minutes=30)
# An upper bound rather than a suggestion. A token valid for a week is a
# standing invitation to join this deployment, and the reason anybody wants a
# long one is that they have not decided when they are installing the server.
MAXIMUM_TOKEN_LIFETIME = timedelta(days=7)


class EnrollmentRejected(Exception):
    """A stable refusal that never says which check failed."""

    def __init__(self) -> None:
        super().__init__("Enrollment was not accepted")


@dataclass(frozen=True, slots=True)
class MintedToken:
    """The token, returned exactly once because it is never stored.

    Only the digest goes to the database, so this value cannot be recovered
    afterwards -- which is the point, and is why the caller has to show it to
    the operator immediately.
    """

    token: str
    token_id: UUID
    label: str
    expires_at: datetime


@dataclass(frozen=True, slots=True)
class EnrolledNode:
    """What a node receives in exchange for its token."""

    server_id: UUID
    label: str
    certificate_pem: str
    ca_certificate_pem: str


class EnrollmentService:
    def __init__(
        self,
        session_factory: SessionFactory,
        token_key_ring: KeyRing,
        current_key_version: int,
    ) -> None:
        self._session_factory = session_factory
        self._key_ring = token_key_ring
        self._current_key_version = current_key_version

    async def mint(
        self,
        *,
        label: str,
        lifetime: timedelta | None = None,
        admin_id: UUID | None = None,
    ) -> MintedToken:
        """Create a token for one node to redeem."""

        # `is None`, not `or`: timedelta(0) is falsy, so `or` would silently
        # turn an explicit zero -- a token valid for no time at all, which is
        # a mistake worth reporting -- into the default half hour.
        window = DEFAULT_TOKEN_LIFETIME if lifetime is None else lifetime
        if window <= timedelta(0) or window > MAXIMUM_TOKEN_LIFETIME:
            raise ValueError(
                f"an enrollment token may last up to {MAXIMUM_TOKEN_LIFETIME.days} days"
            )

        token = issue_opaque_token(self._current_key_version)
        digest = digest_opaque_token(token, self._key_ring, namespace=ENROLLMENT_NAMESPACE)
        expires_at = datetime.now(UTC) + window

        async with self._session_factory() as session:
            # A server already has this name: redeeming would fail on its
            # unique code after the node did its work (AUD-011).
            if await session.scalar(select(VPNServer.id).where(VPNServer.code == label)):
                raise LabelInUse(label)
            row = NodeEnrollmentToken(
                id=uuid4(),
                label=label,
                token_digest=digest.value,
                key_version=digest.key_version,
                expires_at=expires_at,
                created_by_admin_id=admin_id,
            )
            session.add(row)
            # Adding a server is the most consequential thing an admin does
            # here, and left no trail (AUD-011).
            if admin_id is not None:
                add_audit_event(
                    session,
                    actor_kind="admin",
                    actor_id=admin_id,
                    target_kind="vpn_server",
                    target_id=row.id,
                    event_code="server_changed",
                    outcome="succeeded",
                    request_id=uuid4(),
                    reason_code="enrollment_token_minted",
                )
            else:
                # From the server's own CLI (nebula-api enroll-token).
                add_audit_event(
                    session,
                    actor_kind="system",
                    actor_id=None,
                    target_kind="vpn_server",
                    target_id=row.id,
                    event_code="server_changed",
                    outcome="succeeded",
                    request_id=uuid4(),
                    reason_code="enrollment_token_minted",
                )
            await session.commit()
            token_id = row.id

        # The label, never the token. This line lands in container logs.
        _LOGGER.info("minted an enrollment token for %r", label)
        return MintedToken(token=token, token_id=token_id, label=label, expires_at=expires_at)

    async def redeem(
        self,
        *,
        token: str,
        csr_pem: bytes,
        authority: CertificateAuthority,
        public_host: str,
        agent_host: str,
        agent_port: int,
        protocol_profiles: list[str] | None = None,
        wireguard_client_pool: IPv4Network | None = None,
        wireguard_gateway_address: IPv4Address | None = None,
        client_authority_pem: bytes | None = None,
    ) -> EnrolledNode:
        """Exchange a token for a signed certificate and a server record.

        The node supplies a public key and where it can be reached. Everything
        the certificate asserts about *who* it is comes from the token, not
        from the request -- see `sign_node_certificate` for why a requester
        naming itself would be able to impersonate another node.
        """

        try:
            digest = digest_opaque_token(token, self._key_ring, namespace=ENROLLMENT_NAMESPACE)
        except (OpaqueTokenError, ValueError):
            # A malformed token is refused exactly like an unknown one. The
            # difference is visible to whoever sent it and to nobody else.
            raise EnrollmentRejected() from None

        now = datetime.now(UTC)
        async with self._session_factory() as session:
            row = await session.scalar(
                select(NodeEnrollmentToken)
                .where(
                    NodeEnrollmentToken.token_digest == digest.value,
                    NodeEnrollmentToken.key_version == digest.key_version,
                )
                # Locked for the whole exchange: two nodes presenting the same
                # token at once would otherwise both find it unused and both
                # enrol, which is exactly what single-use has to prevent.
                .with_for_update()
            )
            if row is None or not row.is_redeemable(now=now):
                raise EnrollmentRejected()
            # The certificate carries these names and the control plane dials
            # the agent at agent_host: never a name another server already
            # has, which would let one token holder stand in for it (AUD-011).
            if not (_HOST.match(public_host) and _HOST.match(agent_host)):
                raise EnrollmentRejected()
            taken = await session.scalar(
                select(VPNServer.id).where(
                    or_(
                        VPNServer.public_host.in_((public_host, agent_host)),
                        VPNServer.agent_host.in_((public_host, agent_host)),
                    )
                )
            )
            if taken is not None:
                raise EnrollmentRejected()

            try:
                certificate = sign_node_certificate(
                    authority,
                    csr_pem,
                    common_name=row.label,
                    hostnames=certificate_hostnames(public_host, agent_host),
                )
            except PkiError:
                # The token is deliberately left unspent. A node that sent a
                # malformed request should be able to fix it and try again
                # rather than need a new token from an administrator.
                raise EnrollmentRejected() from None

            server = VPNServer(
                id=uuid4(),
                code=row.label,
                display_name=row.label,
                public_host=public_host,
                agent_host=agent_host,
                agent_port=agent_port,
                state=ServerState.ACTIVE.value,
                wireguard_client_pool=(
                    str(wireguard_client_pool) if wireguard_client_pool else None
                ),
                wireguard_gateway_address=(
                    str(wireguard_gateway_address) if wireguard_gateway_address else None
                ),
            )
            session.add(server)
            await session.flush()
            add_audit_event(
                session,
                # The token holder, not yet anyone the control plane knows.
                actor_kind="anonymous",
                actor_id=None,
                target_kind="vpn_server",
                target_id=server.id,
                event_code="server_changed",
                outcome="succeeded",
                request_id=uuid4(),
                reason_code="server_enrolled",
            )

            # What the node says it serves, and each one's ad-block twin (the
            # same inbound). A node enrolled before this sent nothing and gets
            # nothing, as before; a profile this deployment never seeded is
            # skipped, since there is nothing to offer under that code.
            wanted = set(protocol_profiles or [])
            wanted |= {f"{code}-adblock" for code in wanted}
            if wanted:
                for profile in (
                    await session.scalars(
                        select(ProtocolProfile).where(ProtocolProfile.code.in_(wanted))
                    )
                ).all():
                    session.add(
                        ServerProtocolCapability(
                            vpn_server_id=server.id,
                            protocol_profile_id=profile.id,
                            state=CapabilityState.ENABLED.value,
                            validated_profile_version=str(profile.version),
                        )
                    )

            row.used_at = now
            row.vpn_server_id = server.id
            await session.commit()
            server_id = server.id

        _LOGGER.info("enrolled node %r", row.label)
        return EnrolledNode(
            server_id=server_id,
            label=row.label,
            certificate_pem=certificate.decode("ascii"),
            # The CA the node trusts for clients; the node CA when none given.
            ca_certificate_pem=(client_authority_pem or authority.certificate_pem()).decode(
                "ascii"
            ),
        )

    async def revoke(self, token_id: UUID) -> bool:
        """Withdraw an outstanding token. Returns whether anything changed.

        A token already redeemed is not revoked here: it is spent, and the
        thing worth revoking at that point is the node's certificate, which is
        a different operation on a different object.
        """

        async with self._session_factory() as session:
            row = await session.scalar(
                select(NodeEnrollmentToken)
                .where(NodeEnrollmentToken.id == token_id)
                .with_for_update()
            )
            if row is None or row.used_at is not None or row.revoked_at is not None:
                return False
            row.revoked_at = datetime.now(UTC)
            await session.commit()
            return True

    async def outstanding(self) -> list[NodeEnrollmentToken]:
        """Tokens that could still be redeemed right now."""

        now = datetime.now(UTC)
        async with self._session_factory() as session:
            rows = (
                await session.scalars(
                    select(NodeEnrollmentToken).where(
                        NodeEnrollmentToken.used_at.is_(None),
                        NodeEnrollmentToken.revoked_at.is_(None),
                        NodeEnrollmentToken.expires_at > now,
                    )
                )
            ).all()
            return list(rows)


class LabelInUse(ValueError):
    """A server already has the name a new token was asked for."""


# A DNS name or an IPv4/IPv6 literal, nothing else.
_HOST = re.compile(
    r"^(?=.{1,253}$)([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)*$"
    r"|^[0-9A-Fa-f:.]{2,45}$"
)


def certificate_hostnames(public_host: str, agent_host: str) -> list[str]:
    """Every name the control plane might dial this node by.

    Both, because they are frequently different: the public host is what
    clients connect to for VPN traffic, while the agent host is often a
    private address the control plane reaches over an internal network. A
    certificate carrying only one of them fails verification on the other.
    """

    names = [public_host]
    if agent_host and agent_host != public_host:
        names.append(agent_host)
    return names
