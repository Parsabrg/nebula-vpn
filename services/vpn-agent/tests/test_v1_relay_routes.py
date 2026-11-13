"""The relay request route: what it writes for root to apply, and what it refuses."""

import os
import stat
from collections.abc import Iterator
from pathlib import Path, PurePosixPath

import pytest
from fastapi.testclient import TestClient

from nebula_agent.drivers.fake import FakeXrayRunner
from nebula_agent.ledger import OperationLedger
from nebula_agent.main import create_app
from nebula_agent.settings import Settings

TOKEN = "t" * 32
URL = "https://cdn.example.org/v1/relays/germany-via-tehran/up"


@pytest.fixture
def relay_file(tmp_path: Path) -> Path:
    return tmp_path / "relay" / "relay.env"


@pytest.fixture
def client(tmp_path: Path, relay_file: Path) -> Iterator[TestClient]:
    settings = Settings(env="test", relay_request_file=PurePosixPath(str(relay_file)))
    ledger = OperationLedger(PurePosixPath(str(tmp_path / "ledger.jsonl")), 100)
    app = create_app(settings, xray_driver=FakeXrayRunner(), ledger=ledger)
    with TestClient(app) as test_client:
        yield test_client


def test_a_relay_is_written_for_root_to_apply(client: TestClient, relay_file: Path) -> None:
    response = client.post(
        "/v1/relay",
        json={
            "target": "203.0.113.10",
            "ports": [
                {"here": 2053, "proto": "tcp", "there": 8449},
                {"here": 443, "proto": "udp", "there": 8450},
            ],
            "report_url": URL,
            "report_token": TOKEN,
        },
    )

    assert response.status_code == 204
    assert relay_file.read_text(encoding="utf-8").splitlines() == [
        "NEBULA_RELAY_TARGET=203.0.113.10",
        "NEBULA_RELAY_PORTS=2053/tcp:8449 443/udp:8450",
        f"NEBULA_RELAY_REPORT_URL={URL}",
        f"NEBULA_RELAY_REPORT_TOKEN={TOKEN}",
    ]
    if os.name == "posix":
        # The report token is in it.
        assert stat.S_IMODE(relay_file.stat().st_mode) == 0o600


def test_no_ports_means_no_relay(client: TestClient, relay_file: Path) -> None:
    assert client.post("/v1/relay", json={"ports": []}).status_code == 204
    assert relay_file.read_text(encoding="utf-8") == ""


@pytest.mark.parametrize(
    "body",
    [
        # Never the exit's SSH, certificate renewal, panel or agent.
        {"target": "203.0.113.10", "ports": [{"here": 2222, "proto": "tcp", "there": 22}]},
        {"target": "203.0.113.10", "ports": [{"here": 9443, "proto": "tcp", "there": 9443}]},
        {"target": "exit.example.org", "ports": [{"here": 1, "proto": "tcp", "there": 8449}]},
        {"target": "203.0.113.10", "ports": [{"here": 1, "proto": "icmp", "there": 8449}]},
        {"target": "203.0.113.10", "ports": [], "report_url": "http://x/v1/relays/a/up"},
        {"target": "203.0.113.10", "ports": [], "report_token": "short"},
    ],
)
def test_anything_but_a_relay_is_refused(
    client: TestClient, relay_file: Path, body: dict[str, object]
) -> None:
    assert client.post("/v1/relay", json=body).status_code == 422
    assert not relay_file.exists()
