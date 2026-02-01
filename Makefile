# Kalypso Infrastructure - Makefile
# Cluster management, deployment, and verification

.PHONY: help cluster-colima cluster-colima-delete cluster-kind cluster-kind-delete \
        delete-cluster deploy deploy-manual verify verify-ebpf \
        port-forward-grafana port-forward-minio port-forward-argocd lint

COLIMA_PROFILE ?= kalypso
ARGOCD_NAMESPACE ?= argocd
MANIFESTS_DIR ?= manifests

# Component order follows ArgoCD sync waves
COMPONENTS = cert-manager otel istio minio mimir tempo loki pyroscope grafana

help: ## Show this help
	@echo "Kalypso Infrastructure - Available targets:"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-25s\033[0m %s\n", $$1, $$2}'

# ──────────────────────────────────────────────
# Cluster Management
# ──────────────────────────────────────────────

cluster-colima: ## Create Colima + K3s cluster (recommended, eBPF support)
	@./scripts/setup-colima.sh

cluster-colima-delete: ## Delete Colima cluster
	colima delete $(COLIMA_PROFILE)

cluster-kind: ## Create Kind cluster (legacy, no eBPF support)
	kind create cluster --config ./kind-config.yaml

cluster-kind-delete: ## Delete Kind cluster
	kind delete cluster --name kind

delete-cluster: ## Delete current cluster (auto-detect Colima or Kind)
	@if colima list 2>/dev/null | grep -q "^$(COLIMA_PROFILE) .*Running"; then \
		echo "Deleting Colima cluster '$(COLIMA_PROFILE)'..."; \
		colima delete $(COLIMA_PROFILE); \
	elif kind get clusters 2>/dev/null | grep -q "^kind$$"; then \
		echo "Deleting Kind cluster 'kind'..."; \
		kind delete cluster --name kind; \
	else \
		echo "No running cluster found."; \
	fi

# ──────────────────────────────────────────────
# Deployment
# ──────────────────────────────────────────────

deploy: _argocd-install ## Deploy full stack via ArgoCD
	kubectl apply -f argocd/project.yaml
	kubectl apply -f argocd/applicationset.yaml
	@echo ""
	@echo "ArgoCD ApplicationSet deployed. Monitor with:"
	@echo "  kubectl get applications -n $(ARGOCD_NAMESPACE)"
	@echo "  watch kubectl get pods -A"

_argocd-install:
	@helm repo add argo https://argoproj.github.io/argo-helm 2>/dev/null || true
	@helm repo update argo
	helm upgrade -i argocd argo/argo-cd \
		-n $(ARGOCD_NAMESPACE) --create-namespace \
		-f argocd/values.yaml \
		--wait

deploy-manual: ## Deploy all components via Kustomize (no ArgoCD)
	@for component in $(COMPONENTS); do \
		echo "Deploying $$component..."; \
		kubectl kustomize $(MANIFESTS_DIR)/$$component --enable-helm | kubectl apply --server-side -f - || true; \
		echo ""; \
	done
	@echo "All components deployed. Run 'make verify' to check status."

# ──────────────────────────────────────────────
# Verification
# ──────────────────────────────────────────────

verify: ## Check all pod statuses
	@echo "=== Cluster Nodes ==="
	@kubectl get nodes -o wide 2>/dev/null || echo "No cluster found"
	@echo ""
	@echo "=== Pod Status ==="
	@kubectl get pods -A --sort-by=.metadata.namespace 2>/dev/null | \
		grep -E "(NAMESPACE|otel|istio|cert-manager|minio|mimir|tempo|loki|pyroscope|grafana|argocd)" || \
		echo "No matching pods found"
	@echo ""
	@echo "=== ArgoCD Applications ==="
	@kubectl get applications -n $(ARGOCD_NAMESPACE) 2>/dev/null || echo "ArgoCD not installed"

verify-ebpf: ## Verify eBPF support on cluster nodes
	@./scripts/verify-ebpf.sh

# ──────────────────────────────────────────────
# Port Forwarding
# ──────────────────────────────────────────────

port-forward-grafana: ## Port-forward Grafana to localhost:3000
	@echo "Grafana: http://localhost:3000"
	@echo "User: admin"
	@echo "Pass: $$(kubectl get secret -n grafana grafana -o jsonpath='{.data.admin-password}' 2>/dev/null | base64 -d || echo 'run make deploy first')"
	@echo ""
	kubectl port-forward -n grafana svc/grafana 3000:80

port-forward-minio: ## Port-forward MinIO Console to localhost:9001
	@echo "MinIO Console: http://localhost:9001"
	kubectl port-forward -n minio svc/kalypso-minio 9001:9001

port-forward-argocd: ## Port-forward ArgoCD UI to localhost:8080
	@echo "ArgoCD UI: http://localhost:8080"
	@echo "User: admin"
	@echo "Pass: $$(kubectl get secret -n $(ARGOCD_NAMESPACE) argocd-initial-admin-secret -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || echo 'run make deploy first')"
	@echo ""
	kubectl port-forward -n $(ARGOCD_NAMESPACE) svc/argocd-server 8080:443

# ──────────────────────────────────────────────
# Development
# ──────────────────────────────────────────────

lint: ## Validate all Kustomize manifests
	@PASS=0; FAIL=0; \
	for component in $(COMPONENTS); do \
		if kubectl kustomize $(MANIFESTS_DIR)/$$component --enable-helm > /dev/null 2>&1; then \
			echo "  OK  $$component"; \
			PASS=$$((PASS+1)); \
		else \
			echo "  FAIL $$component"; \
			FAIL=$$((FAIL+1)); \
		fi; \
	done; \
	echo ""; \
	echo "Results: $$PASS passed, $$FAIL failed"; \
	test $$FAIL -eq 0
