#!/usr/bin/env bash
# Daily database backup, run on the server by cron:
#   30 3 * * * /opt/mnemos/deploy/lightsail/backup.sh >> /opt/mnemos/backups/backup.log 2>&1
#
# pg_dump -> gzip -> /opt/mnemos/backups (7 days kept) -> bucket under
# backups/ (30 days kept). The upload uses the API image's boto3 and the
# bucket key already in .env, so the instance needs no AWS credentials.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

DIR=/opt/mnemos/backups
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
FILE="mnemos-$STAMP.sql.gz"
mkdir -p "$DIR"

set -a; . ./.env; set +a
docker compose exec -T postgres pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" --no-owner \
  | gzip -9 > "$DIR/$FILE.part"
mv "$DIR/$FILE.part" "$DIR/$FILE"

docker compose run --rm --no-deps -T -v "$DIR:/backups:ro" --entrypoint python server - "$FILE" <<'PY'
import os, sys
from datetime import datetime, timedelta, timezone
import boto3
from botocore.config import Config

s3 = boto3.client(
    "s3",
    endpoint_url=os.environ["S3_ENDPOINT_URL"],
    region_name=os.environ["S3_REGION"],
    aws_access_key_id=os.environ["S3_ACCESS_KEY"],
    aws_secret_access_key=os.environ["S3_SECRET_KEY"],
    config=Config(s3={"addressing_style": "path"}),
)
bucket, name = os.environ["S3_BUCKET"], sys.argv[1]
s3.upload_file(f"/backups/{name}", bucket, f"backups/{name}")
cutoff = datetime.now(timezone.utc) - timedelta(days=30)
old = [o["Key"] for page in s3.get_paginator("list_objects_v2").paginate(Bucket=bucket, Prefix="backups/")
       for o in page.get("Contents", []) if o["LastModified"] < cutoff]
for key in old:
    s3.delete_object(Bucket=bucket, Key=key)
print(f"uploaded backups/{name}; pruned {len(old)}")
PY

find "$DIR" -name 'mnemos-*.sql.gz' -mtime +7 -delete
echo "[backup] $STAMP ok ($(du -h "$DIR/$FILE" | cut -f1))"
