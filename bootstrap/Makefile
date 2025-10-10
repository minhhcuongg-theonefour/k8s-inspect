.PHONY: help install-argocd install-argocd-cli deploy-argocd deploy-bootstrap \
        deploy-app-of-apps deploy-all status watch-apps sync-all refresh-all \
        get-argocd-password port-forward-argocd logs describe diff validate \
        verify test delete-app delete-all-apps uninstall-argocd clean \
        update-repo-url plan-argocd create-argocd-resources apply-argocd \
        apply-argocd-bootstrap apply-argocd-all

#=============================================================================
# Variables
#=============================================================================

REPO_URL ?= https://github.com/minhhcuongg-theonefour/k8s-inspect.git
TARGET_REVISION ?= feat/sync-wave

#=============================================================================
# Help
#=============================================================================

help:
	@echo "Kubeflow Bootstrap Makefile"
	@echo ""
	@echo "Installation Commands:"
	@echo "  install-argocd          - Install ArgoCD in cluster"
	@echo "  install-argocd-cli      - Install ArgoCD CLI locally (macOS)"
	@echo ""
	@echo "Deployment Commands:"
	@echo "  deploy-argocd           - Deploy ArgoCD application"
	@echo "  deploy-bootstrap        - Deploy bootstrap application"
	@echo "  deploy-app-of-apps      - Deploy app-of-apps pattern (RECOMMENDED)"
	@echo "  deploy-all              - Deploy everything"
	@echo ""
	@echo "Management Commands:"
	@echo "  status                  - Show status of all applications"
	@echo "  watch-apps              - Watch applications in real-time"
	@echo "  sync-all                - Sync all applications"
	@echo "  refresh-all             - Refresh all applications"
	@echo ""
	@echo "Access Commands:"
	@echo "  get-argocd-password     - Get ArgoCD admin password"
	@echo "  port-forward-argocd     - Port forward to ArgoCD UI (8080)"
	@echo ""
	@echo "Troubleshooting Commands:"
	@echo "  logs APP=<name>         - View logs for specific application"
	@echo "  describe APP=<name>     - Describe application"
	@echo "  diff APP=<name>         - Show diff for application"
	@echo ""
	@echo "Validation Commands:"
	@echo "  validate                - Validate all manifests"
	@echo "  verify                  - Verify deployment"
	@echo "  test                    - Run tests"
	@echo ""
	@echo "Cleanup Commands:"
	@echo "  delete-app APP=<name>   - Delete specific application"
	@echo "  delete-all-apps         - Delete all Kubeflow applications"
	@echo "  uninstall-argocd        - Uninstall ArgoCD"
	@echo "  clean                   - Clean everything"
	@echo ""
	@echo "Utility Commands:"
	@echo "  update-repo-url REPO=<url> - Update repository URL"
	@echo ""
	@echo "Legacy Commands (for backwards compatibility):"
	@echo "  plan-argocd             - Preview ArgoCD installation"
	@echo "  create-argocd-resources - Install ArgoCD in cluster"
	@echo "  apply-argocd            - Apply ArgoCD application"
	@echo "  apply-argocd-bootstrap  - Apply bootstrap application"
	@echo "  apply-argocd-all        - Install ArgoCD and bootstrap"

#=============================================================================
# Installation Commands
#=============================================================================

install-argocd:
	@echo "Installing ArgoCD..."
	kubectl kustomize --enable-helm ./argocd | kubectl apply -f -
	@echo "Waiting for ArgoCD to be ready..."
	kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=300s
	@echo "ArgoCD installed successfully"

install-argocd-cli:
	@echo "Installing ArgoCD CLI (macOS)..."
	brew install argocd
	@echo "ArgoCD CLI installed"

#=============================================================================
# Deployment Commands
#=============================================================================

deploy-argocd:
	@echo "Deploying ArgoCD application..."
	kubectl apply -f argocd-application.yaml
	@echo "ArgoCD application deployed"

deploy-bootstrap:
	@echo "Deploying bootstrap application..."
	kubectl apply -f argocd-bootstrap.yaml
	@echo "Bootstrap application deployed"

deploy-app-of-apps:
	@echo "Deploying Kubeflow App-of-Apps..."
	@if [ ! -f app-of-apps.yaml ]; then \
		echo "ERROR: app-of-apps.yaml not found. Please create it first."; \
		echo "       See README.md Phase 2 for instructions."; \
		exit 1; \
	fi
	kubectl apply -f app-of-apps.yaml
	@echo "App-of-Apps deployed"
	@echo ""
	@echo "Monitor deployment with: make watch-apps"
	@echo "Check status with: make status"

deploy-all: install-argocd deploy-app-of-apps
	@echo "All components deployed"

#=============================================================================
# Management Commands
#=============================================================================

status:
	@echo "ArgoCD Applications Status:"
	@kubectl get applications -n argocd -o custom-columns=\
		NAME:.metadata.name,\
		SYNC:.status.sync.status,\
		HEALTH:.status.health.status,\
		WAVE:.metadata.annotations.argocd\\.argoproj\\.io/sync-wave 2>/dev/null || \
	kubectl get applications -n argocd -o wide

watch-apps:
	@echo "Watching ArgoCD applications (Ctrl+C to exit)..."
	watch -n 5 'kubectl get applications -n argocd -o custom-columns=NAME:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status,WAVE:.metadata.annotations.argocd\\.argoproj\\.io/sync-wave'

sync-all:
	@echo "Syncing all applications..."
	@kubectl get applications -n argocd -o name | while read app; do \
		echo "Syncing $$app..."; \
		kubectl patch $$app -n argocd --type merge -p '{"operation":{"initiatedBy":{"username":"makefile"},"sync":{"revision":"HEAD"}}}' 2>/dev/null || true; \
	done
	@echo "Sync initiated for all applications"

refresh-all:
	@echo "Refreshing all applications..."
	@if command -v argocd > /dev/null; then \
		argocd app list -o name | xargs -I {} argocd app get {} --refresh; \
	else \
		echo "WARNING: ArgoCD CLI not installed. Install with: make install-argocd-cli"; \
		exit 1; \
	fi
	@echo "All applications refreshed"

#=============================================================================
# Access Commands
#=============================================================================

get-argocd-password:
	@echo "ArgoCD Admin Password:"
	@kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" | base64 -d
	@echo ""

port-forward-argocd:
	@echo "Port forwarding ArgoCD UI to http://localhost:8080"
	@echo "Username: admin"
	@echo "Password: (run 'make get-argocd-password')"
	@echo ""
	@echo "Press Ctrl+C to stop"
	kubectl port-forward svc/argocd-server -n argocd 8080:443

#=============================================================================
# Troubleshooting Commands
#=============================================================================

logs:
	@if [ -z "$(APP)" ]; then \
		echo "ERROR: Please specify APP=<app-name>"; \
		echo "       Example: make logs APP=kubeflow-pipelines"; \
		exit 1; \
	fi
	@echo "Logs for application: $(APP)"
	@if command -v argocd > /dev/null; then \
		argocd app logs $(APP) -n argocd; \
	else \
		echo "WARNING: ArgoCD CLI not installed. Showing pod logs instead..."; \
		kubectl logs -l app.kubernetes.io/instance=$(APP) -n kubeflow --tail=100 -f; \
	fi

describe:
	@if [ -z "$(APP)" ]; then \
		echo "ERROR: Please specify APP=<app-name>"; \
		echo "       Example: make describe APP=kubeflow-pipelines"; \
		exit 1; \
	fi
	@echo "Describing application: $(APP)"
	kubectl describe application $(APP) -n argocd

diff:
	@if [ -z "$(APP)" ]; then \
		echo "ERROR: Please specify APP=<app-name>"; \
		echo "       Example: make diff APP=kubeflow-pipelines"; \
		exit 1; \
	fi
	@echo "Diff for application: $(APP)"
	@if command -v argocd > /dev/null; then \
		argocd app diff $(APP) -n argocd; \
	else \
		echo "ERROR: ArgoCD CLI required. Install with: make install-argocd-cli"; \
		exit 1; \
	fi

#=============================================================================
# Validation Commands
#=============================================================================

validate:
	@echo "Validating ArgoCD application manifests..."
	@for file in apps/kubeflow/*.yaml argocd-*.yaml app-of-apps.yaml 2>/dev/null; do \
		if [ -f "$$file" ]; then \
			echo "  Validating $$file..."; \
			kubectl apply --dry-run=client -f "$$file" > /dev/null; \
		fi \
	done
	@echo "All manifests are valid"

verify:
	@echo "Verifying deployment..."
	@echo ""
	@echo "1. Checking ArgoCD applications..."
	@kubectl get applications -n argocd
	@echo ""
	@echo "2. Checking application health..."
	@UNHEALTHY=$$(kubectl get applications -n argocd -o json | jq -r '.items[] | select(.status.health.status != "Healthy") | .metadata.name' | wc -l | tr -d ' '); \
	if [ "$$UNHEALTHY" -gt 0 ]; then \
		echo "WARNING: $$UNHEALTHY applications are not healthy"; \
		kubectl get applications -n argocd -o json | jq -r '.items[] | select(.status.health.status != "Healthy") | "  - " + .metadata.name + ": " + .status.health.status'; \
	else \
		echo "All applications are healthy"; \
	fi
	@echo ""
	@echo "3. Checking pods..."
	@FAILED=$$(kubectl get pods -A | grep -v Running | grep -v Completed | grep -v NAME | wc -l | tr -d ' '); \
	if [ "$$FAILED" -gt 0 ]; then \
		echo "WARNING: $$FAILED pods are not running"; \
		kubectl get pods -A | grep -v Running | grep -v Completed; \
	else \
		echo "All pods are running"; \
	fi
	@echo ""
	@echo "4. Checking namespaces..."
	@kubectl get namespaces | grep -E 'cert-manager|istio-system|auth|knative|kubeflow' || echo "WARNING: Some namespaces missing"
	@echo ""
	@echo "Verification complete. Review any warnings above."

test: validate verify
	@echo "All tests passed"

#=============================================================================
# Cleanup Commands
#=============================================================================

delete-app:
	@if [ -z "$(APP)" ]; then \
		echo "ERROR: Please specify APP=<app-name>"; \
		echo "       Example: make delete-app APP=kubeflow-pipelines"; \
		exit 1; \
	fi
	@echo "Deleting application: $(APP)"
	kubectl delete application $(APP) -n argocd
	@echo "Application deleted"

delete-all-apps:
	@echo "WARNING: This will delete ALL Kubeflow applications (not ArgoCD itself)"
	@read -p "Are you sure? [y/N] " -n 1 -r; \
	echo; \
	if [ "$$REPLY" = "y" ] || [ "$$REPLY" = "Y" ]; then \
		kubectl delete applications -l app.kubernetes.io/part-of=kubeflow -n argocd 2>/dev/null || true; \
		kubectl delete applications kubeflow-app-of-apps -n argocd 2>/dev/null || true; \
		echo "All Kubeflow applications deleted"; \
	else \
		echo "Cancelled"; \
	fi

uninstall-argocd:
	@echo "WARNING: This will completely remove ArgoCD from the cluster"
	@read -p "Are you sure? [y/N] " -n 1 -r; \
	echo; \
	if [ "$$REPLY" = "y" ] || [ "$$REPLY" = "Y" ]; then \
		kubectl delete applications --all -n argocd 2>/dev/null || true; \
		kubectl kustomize --enable-helm ./argocd | kubectl delete -f - 2>/dev/null || true; \
		kubectl delete namespace argocd 2>/dev/null || true; \
		echo "ArgoCD uninstalled"; \
	else \
		echo "Cancelled"; \
	fi

clean: delete-all-apps
	@echo "Cleanup complete"

#=============================================================================
# Utility Commands
#=============================================================================

update-repo-url:
	@if [ -z "$(REPO)" ]; then \
		echo "ERROR: Please specify REPO=<url>"; \
		echo "       Example: make update-repo-url REPO=https://github.com/myorg/myrepo"; \
		exit 1; \
	fi
	@echo "Updating repository URL to: $(REPO)"
	./update-repo-urls.sh $(REPO) $(TARGET_REVISION)
	@echo "Repository URL updated"

#=============================================================================
# Legacy Commands (backwards compatibility)
#=============================================================================

plan-argocd:
	@echo "Previewing ArgoCD installation..."
	kubectl kustomize --enable-helm ./argocd

create-argocd-resources: install-argocd

apply-argocd: deploy-argocd

apply-argocd-bootstrap: deploy-bootstrap

apply-argocd-all: install-argocd deploy-bootstrap
	@echo "ArgoCD and bootstrap deployed (legacy method)"
	@echo "TIP: Consider using: make deploy-app-of-apps"
