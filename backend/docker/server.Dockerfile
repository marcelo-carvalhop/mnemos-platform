# Multi-stage: build tools never reach the runtime image (§11.7).
# One image, two commands — the API and the worker share the code that
# validates a generation request and the code that executes it.

# ---------- builder ----------
FROM python:3.13-slim AS builder

ENV PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1

RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

WORKDIR /build
COPY backend/pyproject.toml ./
# Resolve dependencies from the manifest alone, so this layer caches until
# the manifest changes rather than on every source edit.
RUN pip install --no-cache-dir '.[dev]' 2>/dev/null || pip install --no-cache-dir .

# ---------- runtime ----------
FROM python:3.13-slim AS runtime

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PATH="/opt/venv/bin:$PATH"

# Runs unprivileged. Nothing in the image needs root.
RUN groupadd --system app && useradd --system --gid app --create-home app

COPY --from=builder /opt/venv /opt/venv

WORKDIR /srv
COPY --chown=app:app backend/ /srv/server/
COPY --chown=app:app shared/ /srv/shared/
COPY --chown=app:app backend/docker/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

WORKDIR /srv/server
USER app

EXPOSE 8000

# Liveness only — no external checks. A database blip must not make the
# orchestrator kill healthy containers (§11.7).
HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=3 \
    CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://localhost:8000/healthz', timeout=2).status==200 else 1)"

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["api"]
