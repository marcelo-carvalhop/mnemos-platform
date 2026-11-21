"""FastAPI dependencies.

This is the only place a request turns into a `user_id`. Every router takes it
from here and never from the request body — §5.5 depends on that: ids are
client-generated, so an id in a payload proves identity and never authority.
"""

from typing import Annotated

from fastapi import Depends, Header, HTTPException, status
from sqlalchemy.orm import Session

from app.auth.service import AccountRequired, AuthError, require_member, verify_access_token
from app.contract import ErrorCode
from app.db import get_session

DbSession = Annotated[Session, Depends(get_session)]


def current_identity(
    session: DbSession,
    authorization: Annotated[str | None, Header()] = None,
) -> tuple[str, str]:
    """Returns `(user_id, device_id)` from the bearer token.

    On an invite-only server the account behind the token must also be a
    member (an email, confirmed when confirmation is on). 403, not 401: the
    token is valid, and refreshing it would not change the answer.
    """
    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="missing bearer token",
            headers={"WWW-Authenticate": "Bearer"},
        )

    try:
        identity = verify_access_token(authorization.split(" ", 1)[1].strip())
    except AuthError as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=str(exc),
            headers={"WWW-Authenticate": "Bearer"},
        ) from exc

    try:
        require_member(session, identity[0])
    except AccountRequired as exc:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN, detail=ErrorCode.ACCOUNT_REQUIRED.value
        ) from exc
    return identity


def current_user_id(
    identity: Annotated[tuple[str, str], Depends(current_identity)],
) -> str:
    return identity[0]


CurrentUser = Annotated[str, Depends(current_user_id)]
Identity = Annotated[tuple[str, str], Depends(current_identity)]
