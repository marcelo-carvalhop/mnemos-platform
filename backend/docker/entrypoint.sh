#!/bin/sh
# One image, two commands (§11.7).
#
# `migrate` is deliberately NOT run by `api` or `worker`. An entrypoint that
# runs migrations works with one replica and races with two, and a failed
# migration becomes a crash loop instead of a failed deploy. Migration is a
# separate one-shot step run before the rollout; §11.4 requires additive
# schema changes, which is what makes migrate-then-deploy safe.
set -eu

case "${1:-api}" in
  api)
    exec uvicorn app.main:app --host 0.0.0.0 --port 8000
    ;;
  api-reload)
    exec uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
    ;;
  worker)
    exec python -m app.worker
    ;;
  migrate)
    exec alembic upgrade head
    ;;
  test)
    shift
    exec pytest "$@"
    ;;
  shell)
    exec /bin/sh
    ;;
  *)
    echo "unknown command: $1" >&2
    echo "usage: entrypoint.sh {api|api-reload|worker|migrate|test|shell}" >&2
    exit 2
    ;;
esac
