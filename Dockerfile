# syntax=docker/dockerfile:1

### =========================
### Build stage
### =========================
FROM python:3.12 AS build-python

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

# System deps for building packages
RUN apt-get update && apt-get install -y \
    build-essential \
    gettext \
    libpq-dev \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install uv
COPY --from=ghcr.io/astral-sh/uv:0.10.8 /uv /uvx /bin/

ENV UV_COMPILE_BYTECODE=1 \
    UV_SYSTEM_PYTHON=1 \
    UV_PROJECT_ENVIRONMENT=/usr/local

# Copy dependency files
COPY pyproject.toml uv.lock ./

# Install dependencies (FIXED: cache mount requires id)
RUN --mount=type=cache,id=uv-cache,target=/root/.cache/uv \
    --mount=type=bind,source=uv.lock,target=uv.lock \
    --mount=type=bind,source=pyproject.toml,target=pyproject.toml \
    uv sync --locked --no-install-project --no-editable


### =========================
### Final runtime stage
### =========================
FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

# Create non-root user
RUN groupadd -r saleor && useradd -r -g saleor saleor

# Runtime system dependencies
RUN apt-get update && apt-get install -y \
    libffi8 \
    libgdk-pixbuf-2.0-0 \
    liblcms2-2 \
    libopenjp2-7 \
    libssl3 \
    libtiff6 \
    libwebp7 \
    libpq5 \
    libmagic1 \
    media-types \
    libcurl4 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# App directories
RUN mkdir -p /app/media /app/static \
    && chown -R saleor:saleor /app/

WORKDIR /app

# Copy python environment from build stage
COPY --from=build-python /usr/local/ /usr/local/

# Copy project files
COPY . /app

# Collect static files
ARG STATIC_URL=/static/
ENV STATIC_URL=${STATIC_URL}

RUN SECRET_KEY=dummy STATIC_URL=${STATIC_URL} \
    python manage.py collectstatic --no-input

# Switch to non-root user
USER saleor

EXPOSE 8000

# Run server
CMD ["uvicorn", "saleor.asgi:application", "--host=0.0.0.0", "--port=8000", "--workers=2", "--lifespan=on", "--ws=none", "--no-server-header", "--no-access-log", "--timeout-keep-alive=35", "--timeout-graceful-shutdown=30", "--limit-max-requests=10000"]
