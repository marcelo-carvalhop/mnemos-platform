"""Production configuration must fail loudly, not silently (§8.2, §4.3)."""

import pytest

from app.config import DEV_JWT_SECRET, Settings


def _production(**overrides) -> Settings:
    base = {
        "environment": "production",
        "jwt_secret": "x" * 40,
        "require_attestation": True,
        "enable_docs": False,
        # What "correct" means grew: attestation switched on with nothing
        # configured verifies nothing and rejects everyone at the same time.
        "play_integrity_package": "br.com.flashcards",
        "google_credentials_json": '{"type":"service_account"}',
    }
    return Settings(**{**base, **overrides})


def test_a_correct_production_config_passes():
    _production().validate_for_production()


def test_development_defaults_never_reach_production():
    with pytest.raises(RuntimeError, match="development default"):
        _production(jwt_secret=DEV_JWT_SECRET).validate_for_production()


def test_a_short_signing_key_is_rejected():
    """Everything works with a weak key — the tokens are just forgeable."""
    with pytest.raises(RuntimeError, match="32 bytes"):
        _production(jwt_secret="curta-demais").validate_for_production()


def test_attestation_cannot_be_off_in_production():
    """Section 7.7.1 — without it the one-per-lifetime free tier is unlimited."""
    with pytest.raises(RuntimeError, match="ATTESTATION"):
        _production(require_attestation=False).validate_for_production()


def test_swagger_is_off_in_production_even_if_enabled():
    """§4.3 — guaranteed by the property, not by the validator.

    Asserted here rather than in validate_for_production, where the check
    would be unreachable and would read like protection it does not provide.
    """
    settings = _production(enable_docs=True)
    assert settings.docs_enabled is False


def test_development_is_never_blocked():
    Settings(environment="development").validate_for_production()


def test_attestation_on_with_no_verifier_is_rejected():
    """§8.1 — the two ways of being wrong at once.

    An unconfigured verifier refuses every genuine device, and the free tier
    is one generation per lifetime, so getting this wrong in the other
    direction hands out unlimited allowances. Neither should be reachable by
    forgetting an environment variable.
    """
    with pytest.raises(RuntimeError, match="neither Play Integrity nor App Attest"):
        _production(
            play_integrity_package="", google_credentials_json=""
        ).validate_for_production()


def test_app_attest_alone_is_enough_to_boot():
    """An iOS-only launch is a real configuration, not a misconfiguration."""
    _production(
        play_integrity_package="",
        google_credentials_json="",
        app_attest_app_id="TEAMID.br.com.flashcards",
        app_attest_root_pem="-----BEGIN CERTIFICATE-----\nx\n-----END CERTIFICATE-----",
    ).validate_for_production()
