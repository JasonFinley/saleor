### Build and install packages
FROM python:3.12 AS build-python

# 安裝基礎套件
RUN apt-get -y update \
  && apt-get install -y gettext \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

# 設定工作目錄
WORKDIR /app

# 安裝 Poetry 並停用虛擬環境建立
RUN pip install poetry==1.7.0
RUN poetry config virtualenvs.create false

# 複製依賴清單並安裝
COPY poetry.lock pyproject.toml /app/
RUN poetry install --no-root

### Final image
FROM python:3.12-slim

# 建立並設定用戶
RUN groupadd -r saleor && useradd -r -g saleor saleor

# 安裝運行 Saleor 所需的系統庫
RUN apt-get update \
  && apt-get install -y \
  libcairo2 \
  libgdk-pixbuf-2.0-0 \
  liblcms2-2 \
  libopenjp2-7 \
  libpango-1.0-0 \
  libpangocairo-1.0-0 \
  libssl3 \
  libtiff6 \
  libwebp7 \
  libxml2 \
  libpq5 \
  libmagic1 \
  media-types \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

# 建立媒體與靜態檔案目錄
RUN mkdir -p /app/media /app/static \
  && chown -R saleor:saleor /app/

# 從 build 階段複製已安裝好的 Python 套件
COPY --from=build-python /usr/local/lib/python3.12/site-packages/ /usr/local/lib/python3.12/site-packages/
COPY --from=build-python /usr/local/bin/ /usr/local/bin/

# 複製專案代碼
COPY . /app
WORKDIR /app

# 設定環境變數並收集靜態資源
ARG STATIC_URL
ENV STATIC_URL=${STATIC_URL:-/static/}
RUN SECRET_KEY=dummy STATIC_URL=${STATIC_URL} python3 manage.py collectstatic --no-input

# 確保權限正確並切換到非 root 用戶
RUN chown -R saleor:saleor /app/
USER saleor

EXPOSE 8000
ENV PYTHONUNBUFFERED=1

# 容器啟動指令 (使用 gunicorn)
CMD ["gunicorn", "--bind", ":8000", "--workers", "4", "--worker-class", "saleor.asgi.gunicorn_worker.UvicornWorker", "saleor.asgi:application"]