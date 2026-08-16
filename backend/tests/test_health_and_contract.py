"""Wave 0 verification: the API answers and the contract matches its source.

These tests need no database. `/readyz` is exercised against the real stack by
the integration check in CI (plan §7); here we prove the route shape, the
operation ids the Dart codegen depends on, and that the generated Python
contract still agrees with contract.yaml.
"""

import pathlib

import yaml
from fastapi.testclient import TestClient

from app import contract
from app.main import app

client = TestClient(app)

ROOT = pathlib.Path(__file__).resolve().parents[2]


def test_healthz_is_ok_and_touches_nothing():
    response = client.get("/healthz")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_contract_endpoint_matches_generated_module():
    response = client.get("/v1/contract")
    assert response.status_code == 200
    body = response.json()

    assert body["contract_version"] == contract.CONTRACT_VERSION
    assert body["card_limits"]["front_max_graphemes"] == contract.FRONT_MAX_GRAPHEMES
    assert body["card_limits"]["back_max_graphemes"] == contract.BACK_MAX_GRAPHEMES


def test_generated_contract_matches_yaml():
    """The generated module must not drift from its source.

    CI also runs `python shared/generate.py --check`; this catches the same
    class of failure from inside the test suite, where it is easier to see.
    """
    source = yaml.safe_load((ROOT / "shared" / "contract.yaml").read_text(encoding="utf-8"))

    assert contract.CONTRACT_VERSION == source["version"]
    assert contract.FRONT_MAX_GRAPHEMES == source["card_limits"]["front_max_graphemes"]
    assert contract.BACK_MAX_GRAPHEMES == source["card_limits"]["back_max_graphemes"]
    assert contract.DESIRED_RETENTION == source["scheduling"]["desired_retention"]
    assert contract.DEFAULT_DAY_CUTOFF_HOUR == source["scheduling"]["default_day_cutoff_hour"]

    assert [g.value for g in contract.Grade] == [g["value"] for g in source["grades"]]
    assert [s.value for s in contract.ReviewSource] == source["review_sources"]
    assert [s.value for s in contract.CardStatus] == source["card_statuses"]
    assert [e.value for e in contract.ErrorCode] == source["error_codes"]


def test_grade_wire_values_are_stable():
    """§5.2 — the wire value is the contract. Renumbering corrupts history."""
    assert contract.Grade.ERREI == 1
    assert contract.Grade.DIFICIL == 2
    assert contract.Grade.BOM == 3
    assert contract.Grade.FACIL == 4


def test_every_route_declares_an_operation_id():
    """§4.3 — without explicit ids the generated Dart client is unreadable."""
    schema = app.openapi()
    missing = [
        f"{method.upper()} {path}"
        for path, methods in schema["paths"].items()
        for method, operation in methods.items()
        if "operationId" not in operation
    ]
    assert not missing, f"routes without an operationId: {missing}"


def test_operation_ids_are_unique():
    schema = app.openapi()
    ids = [
        operation["operationId"]
        for methods in schema["paths"].values()
        for operation in methods.values()
    ]
    assert len(ids) == len(set(ids)), f"duplicate operationIds: {ids}"


def test_every_route_declares_a_response_model():
    """Otherwise the generated client types half the API as `dynamic`.

    Checked against whichever 2xx the route actually declares, not against 200
    alone: enqueueing a generation answers 202, because the work has been
    accepted and not done, and demanding 200 everywhere would push routes into
    lying about that.
    """
    schema = app.openapi()
    untyped = []
    for path, methods in schema["paths"].items():
        for method, operation in methods.items():
            responses = operation.get("responses", {})
            success = [
                body
                for code, body in responses.items()
                if code.isdigit() and 200 <= int(code) < 300
            ]
            if not success:
                untyped.append(f"{method.upper()} {path} (no 2xx at all)")
                continue
            if not any(
                "schema" in body.get("content", {}).get("application/json", {})
                for body in success
            ):
                untyped.append(f"{method.upper()} {path}")
    assert not untyped, f"routes without a typed success response: {untyped}"


def test_error_codes_stringify_as_their_wire_value():
    """The regression that put "ErrorCode.TOPIC_TOO_VAGUE" in the database.

    `class X(str, Enum)` stringifies as "X.MEMBER" on Python 3.11+; StrEnum
    stringifies as the value. Anything that reaches a column or a JSON body
    through str() or an f-string depends on this, so it is pinned rather than
    left to the next person to rediscover.
    """
    from app.contract import CardStatus, ErrorCode, ReviewSource

    assert str(ErrorCode.TOPIC_TOO_VAGUE) == "topic_too_vague"
    assert f"{ErrorCode.QUOTA_EXHAUSTED}" == "quota_exhausted"
    assert str(ReviewSource.MULTIPLE_CHOICE) == "multiple_choice"
    assert str(CardStatus.SUSPENDED) == "suspended"
