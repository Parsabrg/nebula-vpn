import ssl

from nebula_agent.serve import build_uvicorn_config
from nebula_agent.settings import Settings


def test_config_binds_the_agent_operation_surface() -> None:
    config = build_uvicorn_config(Settings(env="test"))

    assert config.host == "0.0.0.0"  # noqa: S104 - asserting the value serve.py binds, not a live bind
    assert config.port == 9443


def test_config_requires_a_client_certificate() -> None:
    config = build_uvicorn_config(Settings(env="test"))
    assert config.ssl_cert_reqs == ssl.CERT_REQUIRED


def test_config_uses_the_configured_certificate_paths() -> None:
    settings = Settings(
        env="test",
        agent_tls_cert_file="/run/nebula-secrets/agent_tls_cert",
        agent_tls_key_file="/run/nebula-secrets/agent_tls_key",
        agent_trusted_client_ca_file="/run/nebula-secrets/agent_trusted_client_ca",
    )
    config = build_uvicorn_config(settings)

    assert config.ssl_certfile == "/run/nebula-secrets/agent_tls_cert"
    assert config.ssl_keyfile == "/run/nebula-secrets/agent_tls_key"
    assert config.ssl_ca_certs == "/run/nebula-secrets/agent_trusted_client_ca"


def test_config_disables_access_logging() -> None:
    config = build_uvicorn_config(Settings(env="test"))
    assert config.access_log is False


def test_keeps_idle_connections_longer_than_the_control_plane() -> None:
    # The control plane drops its idle connection after 60 s; this end must
    # not close first, or a reused connection fails mid-request.
    assert build_uvicorn_config(Settings(env="test")).timeout_keep_alive == 120
