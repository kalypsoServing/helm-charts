# syntax=docker/dockerfile:1
FROM ghcr.io/astral-sh/uv:0.6.6 AS uv

FROM python:3.11-slim AS build

COPY --from=uv /uv /uvx /bin/

WORKDIR /app
ENV UV_COMPILE_BYTECODE=1 UV_LINK_MODE=copy

# 의존성 레이어 (pyproject.toml만 — 코드 변경시 캐시 유지)
COPY pyproject.toml .
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --no-install-project --no-dev

# 소스 복사 후 프로젝트 설치
COPY src/ src/
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --no-dev

# Runtime stage
FROM python:3.11-slim

WORKDIR /app
COPY --from=build /app /app

ENV PATH="/app/.venv/bin:$PATH"
ENV HOST=0.0.0.0
ENV PORT=8000

# Git metadata for Pyroscope source code integration (캐시 최적화: 맨 하단 배치)
ARG GIT_REPOSITORY
ARG GIT_REF=unknown
ARG GIT_REF_NAME=unknown
ARG GIT_ROOT_PATH=sample-fastapi
ENV GIT_REPOSITORY=${GIT_REPOSITORY}
ENV GIT_REF=${GIT_REF}
ENV GIT_REF_NAME=${GIT_REF_NAME}
ENV GIT_ROOT_PATH=${GIT_ROOT_PATH}

EXPOSE 8000
CMD ["uvicorn", "sample_fastapi.main:app", "--host", "0.0.0.0", "--port", "8000"]
