"""Object storage for uploads (§7.2, §11.7).

A PDF or a photo never travels through the API process. The client asks for a
pre-signed PUT, uploads straight to the bucket, and sends only the key; the
worker fetches the object by that key. The API therefore never holds a
multi-megabyte body in memory, and the two containers scale independently.
"""

from __future__ import annotations

import boto3
from botocore.config import Config
from botocore.exceptions import BotoCoreError, ClientError

from app.config import get_settings

# Kept in sync with §7.2's limits. The pre-signed URL carries the content-type
# so a client cannot upload a 400 MB video to a key it asked for as a PDF.
UPLOAD_TTL_SECONDS = 900

ALLOWED_CONTENT_TYPES = {
    "application/pdf",
    "image/jpeg",
    "image/png",
    "image/webp",
}


class UploadUnavailable(Exception):
    """The object could not be fetched or the URL could not be signed.

    Infrastructure, not the user — §7.7 refunds this.
    """


def _client(*, public: bool = False):
    """The storage client.

    `public=True` signs against the endpoint a phone can reach; everything
    else talks to storage over the internal network.
    """
    settings = get_settings()
    return boto3.client(
        "s3",
        endpoint_url=settings.s3_public_endpoint if public else settings.s3_endpoint_url,
        aws_access_key_id=settings.s3_access_key,
        aws_secret_access_key=settings.s3_secret_key,
        region_name=settings.s3_region,
        # MinIO speaks path-style; so does S3. Virtual-host style would need
        # DNS per bucket, which the local stack does not have.
        config=Config(signature_version="s3v4", s3={"addressing_style": "path"}),
    )


def presign_upload(key: str, content_type: str) -> str:
    """A URL the client can PUT to directly (§7.2)."""
    if content_type not in ALLOWED_CONTENT_TYPES:
        raise ValueError(f"content type not allowed: {content_type}")

    settings = get_settings()
    try:
        return _client(public=True).generate_presigned_url(
            "put_object",
            Params={
                "Bucket": settings.s3_bucket,
                "Key": key,
                "ContentType": content_type,
            },
            ExpiresIn=UPLOAD_TTL_SECONDS,
        )
    except (BotoCoreError, ClientError) as exc:
        raise UploadUnavailable(str(exc)) from exc


def fetch(key: str) -> tuple[str, bytes]:
    """Reads an uploaded object. Returns its content type and its bytes."""
    settings = get_settings()
    try:
        response = _client().get_object(Bucket=settings.s3_bucket, Key=key)
        return (
            response.get("ContentType") or "application/octet-stream",
            response["Body"].read(),
        )
    except (BotoCoreError, ClientError) as exc:
        raise UploadUnavailable(f"{key}: {exc}") from exc


def delete(key: str) -> None:
    """§8.4 — the source material is not kept after the cards are staged."""
    settings = get_settings()
    try:
        _client().delete_object(Bucket=settings.s3_bucket, Key=key)
    except (BotoCoreError, ClientError) as exc:  # noqa: BLE001
        # Failing to delete must not fail a job whose cards are already
        # staged. The bucket has a lifecycle rule as the backstop.
        raise UploadUnavailable(f"{key}: {exc}") from exc
