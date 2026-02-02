"""Pyroscope auto-injection bootstrap for OTel autoinstrumentation.

Loaded via OTel's sitecustomize.py (after OTel initialization completes).
Patches FastAPI.__init__ to inject Pyroscope tag middleware and
PyroscopeSpanProcessor automatically, with no application code changes.
"""

import logging
import os

logger = logging.getLogger("pyroscope_bootstrap")

_PYROSCOPE_SERVER = os.getenv("PYROSCOPE_SERVER_ADDRESS")

if _PYROSCOPE_SERVER:
    import platform

    import pyroscope

    def _otel_resource(key: str, default: str = "unknown") -> str:
        """Extract a value from OTEL_RESOURCE_ATTRIBUTES."""
        for pair in os.getenv("OTEL_RESOURCE_ATTRIBUTES", "").split(","):
            if "=" in pair:
                k, v = pair.split("=", 1)
                if k.strip() == key:
                    return v.strip()
        return default

    _service_name = os.getenv("OTEL_SERVICE_NAME", "unknown")

    pyroscope.configure(
        application_name=_service_name,
        server_address=_PYROSCOPE_SERVER,
        tags={
            "service_name": _service_name,
            "namespace": _otel_resource("k8s.namespace.name"),
            "pod": _otel_resource("k8s.pod.name"),
            "service_repository": os.getenv("GIT_REPOSITORY", ""),
            "service_git_ref": os.getenv("GIT_REF", "unknown"),
            "service_git_ref_name": os.getenv("GIT_REF_NAME", "unknown"),
            "service_root_path": os.getenv("GIT_ROOT_PATH", ""),
            "service_version": os.getenv("APP_VERSION", "unknown"),
            "env": os.getenv("ENV", "unknown"),
            "runtime_version": platform.python_version(),
        },
    )
    logger.info("Pyroscope configured: server=%s, app=%s", _PYROSCOPE_SERVER, _service_name)

    # ---- FastAPI monkey-patch ----
    # OTel replaces Starlette with _InstrumentedStarlette, but leaves FastAPI untouched.
    # We patch FastAPI.__init__ so that when user code creates FastAPI(), our middleware
    # and SpanProcessor are injected automatically.

    _span_processor_registered = False

    def _patch_fastapi():
        """Monkey-patch FastAPI.__init__ to inject middleware and SpanProcessor."""
        from fastapi import FastAPI

        _original_init = FastAPI.__init__

        def _patched_init(self, *args, **kwargs):
            _original_init(self, *args, **kwargs)
            _inject_middleware(self)
            _register_span_processor()

        FastAPI.__init__ = _patched_init
        logger.info("FastAPI.__init__ patched for Pyroscope injection")

    def _inject_middleware(app):
        """Add Pyroscope tag middleware to the app."""
        from starlette.requests import Request
        from starlette.routing import Match

        async def pyroscope_tag_middleware(request: Request, call_next):
            http_route = request.url.path
            for route in app.routes:
                match, _ = route.matches(request.scope)
                if match == Match.FULL:
                    http_route = getattr(route, "path", http_route)
                    break
            with pyroscope.tag_wrapper({"http_route": http_route, "http_method": request.method}):
                response = await call_next(request)
            return response

        app.middleware("http")(pyroscope_tag_middleware)
        logger.info("Pyroscope tag middleware injected")

    def _register_span_processor():
        """Register PyroscopeSpanProcessor once (TracerProvider is ready at this point)."""
        global _span_processor_registered
        if _span_processor_registered:
            return
        try:
            from opentelemetry import trace
            from pyroscope.otel import PyroscopeSpanProcessor

            provider = trace.get_tracer_provider()
            if hasattr(provider, "add_span_processor"):
                provider.add_span_processor(PyroscopeSpanProcessor())
                _span_processor_registered = True
                logger.info("PyroscopeSpanProcessor registered")
            else:
                logger.warning(
                    "TracerProvider does not support add_span_processor; "
                    "PyroscopeSpanProcessor not registered"
                )
        except Exception:
            logger.warning("Failed to register PyroscopeSpanProcessor", exc_info=True)

    _patch_fastapi()
