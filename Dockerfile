# ═══════════════════════════════════════════════════════════════════
# CP2 — Dockerfile production-ready (multi-stage, non-root, healthcheck)
# Bản 1 stage ban đầu giữ ở Dockerfile.single để so sánh dung lượng.
# ═══════════════════════════════════════════════════════════════════

# ---------- Stage 1: builder — cài dependency, được phép nặng ----------
FROM python:3.11-slim AS builder

WORKDIR /build

# Copy requirements trước để layer pip install được cache khi chỉ sửa code
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# ---------- Stage 2: runtime — chỉ mang theo kết quả ----------
FROM python:3.11-slim AS runtime

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 

WORKDIR /app

COPY --from=builder /install /usr/local

# Tạo user thường trước khi copy code để gán quyền sở hữu
RUN useradd --create-home --uid 10001 appuser

COPY --chown=appuser:appuser app ./app
COPY --chown=appuser:appuser utils ./utils

USER appuser

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import os, urllib.request; urllib.request.urlopen('http://127.0.0.1:' + os.environ.get('PORT', '8000') + '/health', timeout=4).read()" || exit 1

# sh -c để shell mở rộng ${PORT}; exec để uvicorn là PID 1 và nhận SIGTERM trực tiếp
CMD ["sh", "-c", "exec uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000}"]
