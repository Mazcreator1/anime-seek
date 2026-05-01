############################################################
# Stage 1: build environment – compile wheels, install deps
############################################################
FROM python:3.10-slim AS builder

USER root
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      build-essential \
      python3-dev \
      portaudio19-dev \
      libffi-dev \
      libgl1 \
      libglib2.0-0 \
      libsm6 \
      libxrender1 \
      libxext6 \
      ffmpeg \
      libpq-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Python deps
COPY requirements.txt .

# 1) Clean any pre-existing fastapi/pydantic/starlette in the builder
# 2) Install all requirements EXCEPT PyAudio (it fails to build in Docker)
# 3) Install both psycopg drivers
RUN pip install --no-cache-dir --upgrade pip && \
    pip uninstall -y fastapi starlette pydantic fastapi-cli fastapi-cloud-cli || true && \
    rm -rf /usr/local/lib/python3.10/site-packages/fastapi* \
           /usr/local/lib/python3.10/site-packages/starlette* \
           /usr/local/lib/python3.10/site-packages/pydantic* && \
    # create a temp requirements file without PyAudio
    grep -i -v '^PyAudio' requirements.txt > /tmp/requirements-no-pyaudio.txt && \
    pip install --no-cache-dir -r /tmp/requirements-no-pyaudio.txt && \
    # Postgres drivers (cover both psycopg v3 and psycopg2 import paths)
    pip install --no-cache-dir "psycopg[binary]>=3.1" "psycopg2-binary>=2.9"

# If 'dejavu' exists, run 2to3 via the stdlib module (compat)
RUN if [ -d "/usr/local/lib/python3.10/site-packages/dejavu" ]; then \
      python3 -m lib2to3 -w /usr/local/lib/python3.10/site-packages/dejavu; \
    fi

# Patch Dejavu file hash bug (safe if file not present)
RUN sed -i 's/s\.digest()/s.hexdigest()/g' /usr/local/lib/python3.10/site-packages/dejavu/decoder.py || true && \
    find /usr/local/lib/python3.10/site-packages/dejavu/ -name "*.pyc" -delete || true

# App code
COPY . /app

# Ensure uploads exist & writable at build time
RUN mkdir -p /app/uploads /app/uploads/favorites /app/static/user_avatars && \
    chmod -R 777 /app/uploads /app/static/user_avatars


############################################################
# Stage 2: runtime environment – minimal image
############################################################
FROM tiangolo/uvicorn-gunicorn-fastapi:python3.10 AS runtime

USER root
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      libgl1 \
      libglib2.0-0 \
      libsm6 \
      libxrender1 \
      libxext6 \
      libportaudio2 \
      ffmpeg \
      libpq5 \
    && rm -rf /var/lib/apt/lists/*

# MySQL shim
RUN pip install --no-cache-dir PyMySQL && \
    python -c "import site, pathlib; p=pathlib.Path(site.getsitepackages()[0])/'MySQLdb.py'; p.write_text('import pymysql\\n' 'pymysql.install_as_MySQLdb()\\n')"

# App config
ENV APP_MODULE=main:app
ENV PORT=8047
ENV PYTHONPATH=/app
ENV GUNICORN_CMD_ARGS="--chdir /app"
ENV TIMEOUT=900
ENV GRACEFUL_TIMEOUT=900
ENV LOG_LEVEL=debug

WORKDIR /app

# Copy site-packages and binaries from builder
COPY --from=builder /usr/local/lib/python3.10/site-packages /usr/local/lib/python3.10/site-packages
COPY --from=builder /usr/local/bin /usr/local/bin

# Copy app code
COPY --from=builder /app /app

#  Force a clean, consistent FastAPI + Pydantic + Starlette install 
# This fixes the "ErrorWrapper" import problem by ensuring the fastapi
# package is self-consistent with pydantic v2.
RUN pip uninstall -y fastapi starlette pydantic fastapi-cli fastapi-cloud-cli || true && \
    rm -rf /usr/local/lib/python3.10/site-packages/fastapi* \
           /usr/local/lib/python3.10/site-packages/starlette* \
           /usr/local/lib/python3.10/site-packages/pydantic* && \
    pip install --no-cache-dir \
        "pydantic>=2.7,<3.0.0" \
        "pydantic-settings>=2.0.0,<3.0.0" \
        "starlette>=0.37.2,<0.41.0" \
        "fastapi==0.115.12"

# Ensure runtime user and permissions
RUN id -u ubuntu >/dev/null 2>&1 || useradd --no-log-init --create-home --shell /bin/bash ubuntu && \
    chown -R ubuntu:ubuntu /app && \
    chmod -R 777 /app/uploads /app/static/user_avatars

USER ubuntu

EXPOSE 8047
# (Entrypoint provided by tiangolo image)
