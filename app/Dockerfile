# STAGE 1: Builder
FROM python:3.9-slim AS builder
WORKDIR /install
COPY requirements.txt .
RUN pip install --prefix=/install -r requirements.txt

# STAGE 2: Runtime
FROM python:3.9-slim
WORKDIR /app

# Copy only the installed packages from builder
COPY --from=builder /install /usr/local
COPY . .

# SRE Best Practice: Run as non-root user for security
RUN useradd -m -u 1000 appuser && chown -R appuser:appuser /app
USER appuser

EXPOSE 5000

# Healthcheck instruction for Docker Engine
HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
  CMD curl -f http://localhost:5000/health || exit 1

CMD ["gunicorn", "--workers=2", "--bind=0.0.0.0:5000", "app:app"]