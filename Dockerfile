# syntax=docker/dockerfile:1
### =========================
### Build stage
### =========================
FROM python:3.12 AS build-python

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

# 安裝構建必要的系統套件
RUN apt-get update && apt-get install -y \
    build-essential \
    gettext \
    libpq-dev \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# 從官方鏡像引入 uv
COPY --from=ghcr.io/astral-sh/uv:0.10.8 /uv /uvx /bin/

ENV UV_COMPILE_BYTECODE=1 \
    UV_SYSTEM_PYTHON=1 \
    UV_PROJECT_ENVIRONMENT=/usr/local

# 複製依賴清單
COPY pyproject.toml uv.lock ./

# 修正：加入具備專案別名的 cache id 以消除警告
RUN --mount=type=cache,id=saleor-project-uv-cache,target=/root/.cache/uv \
    --mount=type=bind,source=uv.lock,target=uv.lock \
    --mount=type=bind,source=pyproject.toml,target=pyproject.toml \
    uv sync --locked --no-install-project --no-editable

### =========================
### Final runtime stage
### =========================
FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

# 建立非 root 用戶以提高安全性
RUN groupadd -r saleor && useradd -r -g saleor saleor

# 安裝 Saleor 執行所需的 Runtime 依賴
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

# 建立靜態與媒體資料夾並授權
RUN mkdir -p /app/media /app/static \
    && chown -R saleor:saleor /app/

# 從 build 階段將安裝好的 python 核心套件與 bin 拷貝過來
COPY --from=build-python /usr/local/ /usr/local/

# 拷貝專案原始碼
COPY . /app

# 靜態檔案預處理 (在 Build 時完成，減少 Runtime 負荷)
ARG STATIC_URL=/static/
ENV STATIC_URL=${STATIC_URL}
RUN SECRET_KEY=dummy-for-collectstatic python manage.py collectstatic --no-input

# 切換到非 root 用戶
USER saleor

# Railway 預設會偵測 8000 或由 PORT 環境變數指定
EXPOSE 8000

# 啟動命令：使用 sh -c 以確保環境變數 $PORT 能被讀取
CMD ["sh", "-c", "uvicorn saleor.asgi:application --host 0.0.0.0 --port ${PORT:-8000} --workers 2 --lifespan on --ws none --no-server-header --no-access-log --timeout-keep-alive 35 --timeout-graceful-shutdown 30 --limit-max-requests 10000"]
