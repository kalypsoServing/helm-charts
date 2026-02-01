"""FastAPI app for LGTM + Pyroscope testing."""

import os
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
            "service.name": os.getenv("OTEL_SERVICE_NAME", "sample-fastapi"),
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
    """Sample endpoint for tracing."""
    return {"item_id": item_id, "q": q}
