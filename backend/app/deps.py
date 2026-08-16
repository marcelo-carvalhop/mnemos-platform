"""FastAPI dependencies.

This is the only place a request turns into a `user_id`. Every router takes it
from here and never from the request body — §5.5 depends on that: ids are
client-generated, so an id in a payload proves identity and never authority.
"""

from typing import Annotated

from fastapi import Depends, Header, HTTPException, status
from sqlalchemy.orm import Session

from app.auth.service import AuthError, verify_access_token
from app.db import get_session


def current_identity(
    authorization: Annotated[str | None, Header()] = None,
) -> tuple[str, str]:
    """Returns `(user_id, device_id)` from the bearer token."""
    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="missing bearer token",
            headers={"WWW-Authenticate": "Bearer"},
        )

    try:
        return verify_access_token(authorization.split(" ", 1)[1].strip())
    except AuthError as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=str(exc),
            headers={"WWW-Authenticate": "Bearer"},
        ) from exc


def current_user_id(
    identity: Annotated[tuple[str, str], Depends(current_identity)],
) -> str:
    return identity[0]


CurrentUser = Annotated[str, Depends(current_user_id)]
Identity = Annotated[tuple[str, str], Depends(current_identity)]
DbSession = Annotated[Session, Depends(get_session)]
