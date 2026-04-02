# syntax=docker/dockerfile:1
### =========================
### Build stage
### =========================
FROM python:3.12 AS build-python

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

# 安裝編譯依賴
RUN apt-get update && apt-get install -y \
    build-essential \
    gettext \
    libpq-dev \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# 引入 uv
COPY --from=ghcr.io/astral-sh/uv:0.10.8 /uv /uvx /bin/

ENV UV_COMPILE_BYTECODE=1 \
    UV_SYSTEM_PYTHON=1 \
    UV_PROJECT_ENVIRONMENT=/usr/local

# 複製依賴檔案
COPY pyproject.toml uv.lock ./

# 【最終修正】: 嚴格遵守 Railway 要求，使用帶有前綴的 id
RUN --mount=type=cache,id=saleor-app-uv-cache,target=/root/.cache/uv \
    uv sync --locked --no-install-project --no-editable


### =========================
### Final runtime stage
### =========================
FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

# 建立非 root 用戶
RUN groupadd -r saleor && useradd -r -g saleor saleor

# 執行階段必要套件
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

WORKDIR /app
RUN mkdir -p /app/media /app/static && chown -R saleor:saleor /app/

# 從 build 階段拷貝已安裝的環境
COPY --from=build-python /usr/local/ /usr/local/

# 拷貝程式碼
COPY . /app

# 靜態檔案預處理
ARG STATIC_URL=/static/
ENV STATIC_URL=${STATIC_URL}
RUN SECRET_KEY=dummy-for-build python manage.py collectstatic --no-input

USER saleor
EXPOSE 8000

# 啟動指令：使用 sh -c 以支援 Railway 的 $PORT 注入
CMD ["sh", "-c", "uvicorn saleor.asgi:application --host 0.0.0.0 --port ${PORT:-8000} --workers 2 --lifespan on --ws none --no-server-header --no-access-log --timeout-keep-alive 35 --timeout-graceful-shutdown 30 --limit-max-requests 10000"]
