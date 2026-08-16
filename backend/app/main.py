"""FastAPI application.

Every route declares an explicit `operation_id` and a response model (§4.3).
Without them the generated Dart client gets names derived from paths and types
half the API as `dynamic`.
"""

from fastapi import FastAPI, Response, status
from pydantic import BaseModel, Field

from app import contract
from app.account.router import router as account_router
from app.auth.router import router as auth_router
from app.config import get_settings
from app.db import check_connection
from app.generation.router import router as generation_router
from app.quota.router import router as quota_router
from app.sync.router import router as sync_router
from app.terminal.router import router as terminal_router

settings = get_settings()

# Fails the boot rather than serving forgeable tokens (§8.2).
settings.validate_for_production()

app = FastAPI(
    title="Mnemos API",
    version="0.4.0",
    docs_url="/docs" if settings.docs_enabled else None,
    redoc_url=None,
    # Disabled in production together with the UI. The schema that matters is
    # generated at build time for codegen, not scraped from a running server.
    openapi_url="/openapi.json" if settings.docs_enabled else None,
)

# Registered by convention, one router per module — no barrel file for two
# tracks to collide on (plan §4).
app.include_router(auth_router)
app.include_router(sync_router)
app.include_router(quota_router)
app.include_router(generation_router)
app.include_router(account_router)
app.include_router(terminal_router)


class HealthResponse(BaseModel):
    status: str = Field(examples=["ok"])


class ReadyResponse(BaseModel):
    status: str = Field(examples=["ready", "not_ready"])
    database: bool


class CardLimits(BaseModel):
    front_max_graphemes: int
    back_max_graphemes: int


class ContractResponse(BaseModel):
    """The values the client must agree with the server on (§4)."""

    contract_version: int
    card_limits: CardLimits
    mature_interval_days: int
    desired_retention: float
    default_day_cutoff_hour: int
    free_generations_lifetime: int


@app.get(
    "/healthz",
    operation_id="getHealth",
    response_model=HealthResponse,
    tags=["ops"],
    summary="Liveness — checks nothing external",
)
def get_health() -> HealthResponse:
    """Liveness. Deliberately touches no database (§11.7)."""
    return HealthResponse(status="ok")


@app.get(
    "/readyz",
    operation_id="getReady",
    response_model=ReadyResponse,
    tags=["ops"],
    summary="Readiness — checks the database",
)
def get_ready(response: Response) -> ReadyResponse:
    """Readiness. This is what a load balancer reads."""
    database_ok = check_connection()
    if not database_ok:
        response.status_code = status.HTTP_503_SERVICE_UNAVAILABLE
    return ReadyResponse(
        status="ready" if database_ok else "not_ready",
        database=database_ok,
    )


@app.get(
    "/v1/contract",
    operation_id="getContract",
    response_model=ContractResponse,
    tags=["contract"],
    summary="Values shared with the client",
)
def get_contract() -> ContractResponse:
    """Serves the generated contract so a client can detect a version skew.

    The client compiles against its own generated copy; this endpoint exists so
    a mismatch is detectable at runtime rather than as strange behaviour.
    """
    return ContractResponse(
        contract_version=contract.CONTRACT_VERSION,
        card_limits=CardLimits(
            front_max_graphemes=contract.FRONT_MAX_GRAPHEMES,
            back_max_graphemes=contract.BACK_MAX_GRAPHEMES,
        ),
        mature_interval_days=contract.MATURE_INTERVAL_DAYS,
        desired_retention=contract.DESIRED_RETENTION,
        default_day_cutoff_hour=contract.DEFAULT_DAY_CUTOFF_HOUR,
        free_generations_lifetime=contract.FREE_GENERATIONS_LIFETIME,
    )
