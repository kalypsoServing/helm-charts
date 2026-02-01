IMAGE_REPO  ?= sky5367/sample-fastapi
VERSION     ?= $(shell git describe --tags --always --dirty 2>/dev/null || echo dev)
GIT_REPOSITORY := $(shell git remote get-url origin 2>/dev/null | sed 's|git@github.com:|https://github.com/|;s|\.git$$||')
GIT_REF        := $(shell git rev-parse HEAD 2>/dev/null || echo unknown)
GIT_REF_NAME   := $(shell git rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)
GIT_ROOT_PATH  := sample-fastapi

.PHONY: build deploy

build:
	podman build \
	  --build-arg GIT_REPOSITORY=$(GIT_REPOSITORY) \
	  --build-arg GIT_REF=$(GIT_REF) \
	  --build-arg GIT_REF_NAME=$(GIT_REF_NAME) \
	  --build-arg GIT_ROOT_PATH=$(GIT_ROOT_PATH) \
	  -t $(IMAGE_REPO):$(VERSION) \
	  .
	podman push $(IMAGE_REPO):$(VERSION)

deploy:
	kubectl apply -k manifest/
