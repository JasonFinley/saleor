# syntax=docker/dockerfile:1
FROM python:3.12 AS build-python

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

RUN apt-get update && apt-get install -y \
    build-essential \
    gettext \
    libpq-dev \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY --from=ghcr.io/astral-sh/uv:0.10.8 /uv /uvx /bin/

ENV UV_COMPILE_BYTECODE=1 \
    UV_SYSTEM_PYTHON=1 \
    UV_PROJECT_ENVIRONMENT=/usr/local

COPY pyproject.toml uv.lock ./

# 修正 Cache ID 並確保快取隔離
RUN --mount=type=cache,id=saleor-uv-cache,target=/root/.cache/uv \
    uv sync --locked --no-install-project --no-editable

### =========================
### Final runtime stage
### =========================
FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    # 確保產生的 .pyc 檔案不被寫入（減少映像檔體積）
    PYTHONDONTWRITEBYTECODE=1

RUN groupadd -r saleor && useradd -r -g saleor saleor

# 執行階段必要的套件
RUN apt-get update && apt-get install -y \
    libpq5 \
    libmagic1 \
    liblcms2-2 \
    libwebp7 \
    libtiff6 \
    libopenjp2-7 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
RUN mkdir -p /app/media /app/static && chown -R saleor:saleor /app/

# 從 Build 階段拷貝已安裝的套件
COPY --from=build-python /usr/local/lib/python3.12/site-packages /usr/local/lib/python3.12/site-packages
COPY --from=build-python /usr/local/bin /usr/local/bin

# 拷貝專案原始碼
COPY . /app

# 靜態檔案處理
ARG STATIC_URL=/static/
ENV STATIC_URL=${STATIC_URL}
RUN SECRET_KEY=dummy_for_build python manage.py collectstatic --no-input

USER saleor

# Railway 會自動注入 PORT 變數
EXPOSE 8000

CMD ["sh", "-c", "uvicorn saleor.asgi:application --host 0.0.0.0 --port ${PORT:-8000} --workers 2"]
