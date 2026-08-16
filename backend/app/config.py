from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict

# Module-level, not a class attribute: an unannotated attribute on a
# BaseSettings is read as a field and pydantic rejects it.
DEV_JWT_SECRET = "dev-only-not-for-production-0000000000"


class Settings(BaseSettings):
    """Configuration from the environment. Nothing is baked into the image."""

    model_config = SettingsConfigDict(env_file=None, extra="ignore")

    database_url: str = (
        "postgresql+psycopg://flashcards:change-me-locally@localhost:5435/flashcards"
    )

    # §7.2 — MinIO locally, any S3-compatible endpoint in production.
    # Two endpoints, not one. The server and the worker reach storage over the
    # internal network — in compose that is `http://minio:9000`, in production
    # a VPC address — while the pre-signed URL is handed to a phone, which can
    # resolve neither. Signing includes the host, so the URL must be signed
    # against the host the client will actually use.
    s3_endpoint_url: str = "http://localhost:9000"
    s3_public_endpoint_url: str = ""
    s3_access_key: str = "minioadmin"
    s3_secret_key: str = "change-me-locally"
    s3_bucket: str = "uploads"
    s3_region: str = "us-east-1"

    environment: str = "development"
    log_level: str = "INFO"

    # §4.3 — Swagger UI in development, off in production. The API is private
    # to one app; the docs leak no data but publish the full surface.
    enable_docs: bool = True

    # §11.7 — server and worker only. Never the client, never an image layer.
    anthropic_api_key: str = ""

    # §8.2 — signs access tokens. The development fallback keeps
    # `docker compose up` working from a fresh clone; production refuses to
    # start with it (see validate()). At least 32 bytes, per RFC 7518 §3.2 for
    # HMAC-SHA256 — a shorter key weakens the signature rather than failing
    # loudly, which is the wrong direction for a default.
    jwt_secret: str = DEV_JWT_SECRET

    # §8.1 — attestation is required in v1 because the free tier is one
    # generation per lifetime. Disabled in tests and local development, where
    # there is no App Attest to talk to.
    require_attestation: bool = False

    # Android. The service account decodes integrity tokens; the package name
    # is checked against the one in the token so an assertion minted for
    # another app cannot be replayed at us.
    play_integrity_package: str = ""
    google_credentials_json: str = ""

    # iOS. The app id is "<TEAM_ID>.<BUNDLE_ID>", which is what authData
    # commits to. The root is Apple's App Attest CA, in PEM.
    app_attest_app_id: str = ""
    app_attest_root_pem: str = ""

    def google_credentials(self) -> dict:
        import json

        return json.loads(self.google_credentials_json)

    @property
    def s3_public_endpoint(self) -> str:
        """Where the client uploads. Falls back to the internal endpoint, which
        is right for a single-host deployment and wrong loudly for any other:
        the upload fails with a DNS error naming the container."""
        return self.s3_public_endpoint_url or self.s3_endpoint_url

    @property
    def is_production(self) -> bool:
        return self.environment.lower() in {"production", "prod"}

    @property
    def docs_enabled(self) -> bool:
        return self.enable_docs and not self.is_production

    def validate_for_production(self) -> None:
        """Refuses to run production with development defaults.

        Called at import time by the app. A weak signing key is not the kind of
        mistake that shows up in testing — everything works, and the tokens are
        forgeable. Failing to boot is the only reliable signal.
        """
        if not self.is_production:
            return

        problems = []
        if self.jwt_secret == DEV_JWT_SECRET:
            problems.append("JWT_SECRET is still the development default")
        if len(self.jwt_secret.encode()) < 32:
            problems.append("JWT_SECRET must be at least 32 bytes (RFC 7518 §3.2)")
        if not self.require_attestation:
            # §7.7.1 — the free tier is one generation per lifetime, so an
            # unattested device is an unlimited free tier.
            problems.append("REQUIRE_ATTESTATION must be on in production (§8.1)")
        elif not (self.play_integrity_package and self.google_credentials_json) and not (
            self.app_attest_app_id and self.app_attest_root_pem
        ):
            # Attestation switched on with nothing configured verifies nothing
            # and rejects everyone — the two ways of being wrong at once.
            problems.append(
                "REQUIRE_ATTESTATION is on but neither Play Integrity nor "
                "App Attest is configured (§8.1)"
            )
        # Swagger is not checked here: `docs_enabled` already returns False
        # whenever `is_production` is true, so a check would be dead code that
        # reads like protection. The guarantee lives in the property, and the
        # test asserts it there.

        if problems:
            raise RuntimeError("unsafe production configuration: " + "; ".join(problems))


@lru_cache
def get_settings() -> Settings:
    return Settings()
