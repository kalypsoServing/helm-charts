# OTel eBPF Profiler Image
# Based on: https://github.com/grafana/pyroscope/blob/main/examples/grafana-alloy-auto-instrumentation/ebpf-otel/Dockerfile
# 
# Build for AMD64:
#   docker build -t ebpf-profiler:latest .
# 
# Build for ARM64:
#   Change go1.22.10.linux-amd64.tar.gz to go1.22.10.linux-arm64.tar.gz

FROM ubuntu:22.04 as builder

# Install build dependencies
RUN apt-get update && apt-get -y install wget gcc

# Download and install Go 1.22.10
# For AMD64 (default):
RUN wget https://go.dev/dl/go1.22.10.linux-amd64.tar.gz && \
    tar -C /usr/local -xzf go1.22.10.linux-amd64.tar.gz

# For ARM64, replace the above RUN command with:
# RUN wget https://go.dev/dl/go1.22.10.linux-arm64.tar.gz && \
#     tar -C /usr/local -xzf go1.22.10.linux-arm64.tar.gz

# Download OTel eBPF Profiler (pinned commit for protocol compatibility)
RUN wget https://github.com/open-telemetry/opentelemetry-ebpf-profiler/archive/19cb11e6bf00c04e4f8d793e944e71478f9608d9.tar.gz && \
    mkdir /profiler && \
    tar --strip-components=1 -C /profiler -xzf *.tar.gz

# Build the profiler
WORKDIR /profiler
RUN /usr/local/go/bin/go build .

# Runtime image
FROM ubuntu:22.04

# Install runtime dependencies
RUN apt-get update && apt-get install -y linux-headers-generic && \
    rm -rf /var/lib/apt/lists/*

# Copy profiler binary from builder
COPY --from=builder /profiler/ebpf-profiler /usr/local/bin/

# Set entrypoint
ENTRYPOINT ["/usr/local/bin/ebpf-profiler"]
