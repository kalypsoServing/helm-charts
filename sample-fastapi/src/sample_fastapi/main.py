"""FastAPI app for LGTM + Pyroscope testing."""

import asyncio
import hashlib
import math
import os
import random

from fastapi import FastAPI


def _otel_resource(key: str, default: str = "unknown") -> str:
    """OTEL_RESOURCE_ATTRIBUTES에서 특정 키의 값을 추출."""
    for pair in os.getenv("OTEL_RESOURCE_ATTRIBUTES", "").split(","):
        if "=" in pair:
            k, v = pair.split("=", 1)
            if k.strip() == key:
                return v.strip()
    return default


# Pyroscope initialization
pyroscope_server = os.getenv("PYROSCOPE_SERVER_ADDRESS")
if pyroscope_server:
    import pyroscope
    from opentelemetry import trace
    from pyroscope.otel import PyroscopeSpanProcessor

    pyroscope.configure(
        application_name=os.getenv("OTEL_SERVICE_NAME", "sample-fastapi"),
        server_address=pyroscope_server,
        tags={
            # Grafana tracesToProfiles 연동
            "service_name": os.getenv("OTEL_SERVICE_NAME", "sample-fastapi"),
            "namespace": _otel_resource("k8s.namespace.name"),
            "pod": _otel_resource("k8s.pod.name"),
            # Pyroscope source code integration (v1.18+)
            "service_repository": os.getenv("GIT_REPOSITORY", ""),
            "service_git_ref": os.getenv("GIT_REF", "unknown"),
            "service_git_ref_name": os.getenv("GIT_REF_NAME", "unknown"),
            "service_root_path": os.getenv("GIT_ROOT_PATH", ""),
        },
    )

    # Add Pyroscope Span Processor for Trace-Profile linking
    trace.get_tracer_provider().add_span_processor(PyroscopeSpanProcessor())

app = FastAPI(
    title="sample-fastapi",
    description="LGTM + Pyroscope test application",
    version="0.1.0",
)

@app.get("/")
async def root():
    """Root endpoint."""
    return {"message": "Hello from sample-fastapi", "status": "ok"}


@app.get("/health")
async def health():
    """Health check endpoint."""
    return {"status": "healthy"}


@app.get("/items/{item_id}")
async def read_item(item_id: int, q: str | None = None):
    """Sample endpoint — wall time + CPU time 샘플."""
    # 1) CPU-bound: 해시 반복 연산
    cpu_result = _cpu_heavy(item_id)

    # 2) Wall-time: 비동기 I/O 대기 (네트워크 지연 시뮬레이션)
    await _io_wait()

    # 3) CPU-bound: 수학 연산
    math_result = _math_heavy(item_id)

    return {
        "item_id": item_id,
        "q": q,
        "cpu_hash": cpu_result,
        "math_result": math_result,
    }


def _cpu_heavy(seed: int) -> str:
    """SHA-256 해시를 반복하여 CPU 시간을 소비."""
    data = str(seed).encode()
    for _ in range(50_000):
        data = hashlib.sha256(data).digest()
    return data.hex()[:16]


def _math_heavy(seed: int) -> float:
    """삼각함수 + 로그 연산으로 CPU 시간을 소비."""
    result = 0.0
    for i in range(1, 30_000):
        result += math.sin(seed + i) * math.log(i + 1) / math.sqrt(i)
    return round(result, 6)


async def _io_wait():
    """비동기 sleep으로 wall time을 소비 (I/O 대기 시뮬레이션)."""
    await asyncio.sleep(random.uniform(0.05, 0.15))
