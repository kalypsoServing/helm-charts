FROM ubuntu:22.04 AS builder

RUN apt-get update && apt-get -y install wget gcc

ARG TARGETARCH
RUN if [ "$TARGETARCH" = "arm64" ]; then \
      wget https://go.dev/dl/go1.22.10.linux-arm64.tar.gz -O /tmp/go.tar.gz; \
    else \
      wget https://go.dev/dl/go1.22.10.linux-amd64.tar.gz -O /tmp/go.tar.gz; \
    fi && \
    tar -C /usr/local -xzf /tmp/go.tar.gz && \
    rm /tmp/go.tar.gz

RUN wget https://github.com/open-telemetry/opentelemetry-ebpf-profiler/archive/19cb11e6bf00c04e4f8d793e944e71478f9608d9.tar.gz -O /tmp/profiler.tar.gz && \
    mkdir /profiler && \
    tar --strip-components=1 -C /profiler -xzf /tmp/profiler.tar.gz && \
    rm /tmp/profiler.tar.gz

WORKDIR /profiler
RUN /usr/local/go/bin/go build .

FROM ubuntu:22.04

RUN apt-get update && apt-get install -y linux-headers-generic && \
    rm -rf /var/lib/apt/lists/*

COPY --from=builder /profiler/ebpf-profiler /usr/local/bin/

ENTRYPOINT ["/usr/local/bin/ebpf-profiler"]
