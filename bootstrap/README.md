# Kubeflow Bootstrap - ArgoCD App of Apps

This directory contains ArgoCD Application manifests implementing the "App of Apps" pattern for managing Kubeflow components via GitOps.

---

## 📊 Current Status

### ✅ Recently Fixed (Completed)

| Fix | Status | Description |
|-----|--------|-------------|
| Web Apps Namespace | ✅ FIXED | Changed from `istio-system` to `kubeflow` |
| Model Registry Path | ✅ FIXED | Changed from `base` to `overlays/db` (includes database) |
| Training → Trainer | ✅ FIXED | Renamed file and updated application name for clarity |
| Sync Wave Annotations | ✅ ADDED | All 9 apps now have deployment ordering |

### 📋 Application Coverage

| Status | Count | Percentage |
|--------|-------|------------|
| ✅ Working Applications | 9/9 | 100% |
| ⚠️ Need Fixes | 0/9 | 0% |
| ❌ Missing Applications | 5/14 | 36% |
| **Overall Completion** | **9/14** | **64%** |
| **Production Ready** | ⚠️ **PARTIAL** | Existing apps ready, missing core components |

### 🎯 Deployment Order (Sync Waves)

| Wave | Applications | Deploy Time | Status |
|------|--------------|-------------|--------|
| 0 | common-services (infrastructure) | ~2 min | ✅ Annotated (⚠️ Path needs fix) |
| 1 | profiles, admission-webhook | ~1 min | ❌ Missing (need to create) |
| 2 | pipelines, katib, jupyter | ~2 min | ✅ Annotated |
| 3 | kserve, trainer | ~1 min | ✅ Annotated |
| 4 | web-apps, pvcviewer-controller | ~1 min | ✅ Partially (pvcviewer missing) |
| 5 | spark, model-registry, user-namespace | ~1 min | ✅ Partially (user-namespace missing) |

**Total Deployment Time**: ~8-10 minutes (sequential waves)

### ⚠️ Remaining Issues

#### Critical (Blockers)
1. **common-services path** - Points to `example` (deploys everything) instead of `bootstrap/apps/base/common-services`
2. **Missing Wave 1 apps** - profiles, admission-webhook (core Kubeflow components)
3. **Missing controllers** - pvcviewer-controller (Wave 4)
4. **Missing user setup** - user-namespace (Wave 5)

#### Important (Next Steps)
5. Create `bootstrap/apps/base/common-services/kustomization.yaml` for infrastructure
6. Create `bootstrap/apps/kubeflow/kustomization.yaml` to aggregate all apps
7. Create `bootstrap/app-of-apps.yaml` for centralized management

---

## 📖 Understanding Sync Waves & Previous Issues

### Why Sync Waves Are Critical

**Without sync waves**, ArgoCD deploys all applications **simultaneously** in parallel, which causes:

1. **Race Conditions** - Apps try to use resources before they exist
   - Example: KServe tries to create Istio VirtualServices before Istio CRDs exist → **FAILS**
   - Example: Pipelines tries to use cert-manager certificates before cert-manager is ready → **FAILS**

2. **Dependency Failures** - Components depend on infrastructure that isn't ready
   - Webhooks need certificates from cert-manager
   - All apps need Istio service mesh to be operational
   - Web apps need profiles/namespaces to exist first

3. **Unpredictable Behavior** - Deployment order is random, success is luck-based
   - Sometimes it works (lucky timing), sometimes it fails
   - Makes troubleshooting nearly impossible

**With sync waves**, deployment is:
- ✅ **Predictable** - Always deploys in the same order
- ✅ **Reliable** - Dependencies are guaranteed to be ready
- ✅ **Debuggable** - Clear which wave failed and why
- ✅ **Self-healing** - If a wave fails, it retries automatically

### What Was Missing in Previous Implementation

The previous implementation had **3 configuration errors** that would cause deployment failures:

#### 1. **web-apps Wrong Namespace** (`istio-system` → `kubeflow`)
**Why it failed:**
- Web applications were configured to deploy to `istio-system` namespace
- But they need to run in `kubeflow` namespace where:
  - User profiles exist
  - RBAC permissions are configured
  - Service mesh sidecars are properly injected

**Symptom without fix:**
- Pods would fail to start due to missing ServiceAccounts
- RBAC errors: "cannot get/list resources in namespace istio-system"
- Services unreachable due to incorrect mesh configuration

#### 2. **model-registry Missing Database** (`base` → `overlays/db`)
**Why it failed:**
- The `base` kustomization only includes the model registry service
- It doesn't include the MySQL database required for persistence
- Without database, the service has nowhere to store model metadata

**Symptom without fix:**
- Model registry pod crashes immediately: "Cannot connect to database"
- CrashLoopBackOff state
- Users cannot register or track models

#### 3. **training Named Wrong** (should be `trainer`)
**Why it was confusing:**
- File was named `training.yaml` but deploys Trainer (v2), not Training Operator (v1)
- Application name was `kubeflow-training` which is misleading
- This repository uses the newer Trainer v2, not the older Training Operator

**Impact:**
- Not a deployment failure, but causes confusion
- Developers might deploy both thinking they're different
- Documentation and troubleshooting becomes harder

### How Sync Waves Prevent These Issues

```
Wave 0: Infrastructure (Cert-Manager, Istio, Dex, etc.)
  ↓ Wait for all resources to be Healthy
Wave 1: Core Kubeflow (Profiles, Admission Webhook)
  ↓ Wait for all resources to be Healthy
Wave 2: ML Platform (Pipelines, Katib, Jupyter)
  ↓ Wait for all resources to be Healthy
Wave 3: Serving & Training (KServe, Trainer)
  ↓ Wait for all resources to be Healthy
Wave 4: Web Apps (Dashboard, Volume UI, etc.)
  ↓ Wait for all resources to be Healthy
Wave 5: Additional Services (Spark, Model Registry, etc.)
```

Each wave:
1. Waits for previous wave to be 100% healthy
2. Deploys all apps in the current wave
3. Retries automatically if anything fails (up to 5 times)
4. Only proceeds to next wave when current wave is stable

---

## 🚨 Critical Issues (Remaining)

### 1. Common Services Path Error (CRITICAL)
**File**: `apps/kubeflow/common-services.yaml`
```yaml
# Current (WRONG):
path: example  # This deploys ENTIRE Kubeflow stack

# Should be:
path: bootstrap/apps/base/common-services
```
**Impact**: Would deploy 500+ resources in wrong order, causing failures
**Status**: ⚠️ **NOT YET FIXED** - Requires creating common-services kustomization first

### 2. Missing Core Applications (CRITICAL)
**What's missing:**
- `profiles.yaml` - User namespace management (Wave 1)
- `admission-webhook.yaml` - PodDefaults support (Wave 1)
- `pvcviewer-controller.yaml` - PVC viewing in UI (Wave 4)
- `user-namespace.yaml` - Default user setup (Wave 5)

**Impact**: Without these, Kubeflow is not fully functional
**Status**: ⚠️ **NOT YET CREATED** - See Phase 1.2 below for creation commands

---

## ✅ Completed Fixes

The following fixes have already been applied:

### ✅ Fix 1: Web Apps Namespace (COMPLETED)
```bash
# ALREADY APPLIED - namespace changed from istio-system to kubeflow
# File: apps/kubeflow/web-apps.yaml
```

### ✅ Fix 2: Model Registry Path (COMPLETED)
```bash
# ALREADY APPLIED - path changed from base to overlays/db
# File: apps/kubeflow/model-registry.yaml
```

### ✅ Fix 3: Rename Training to Trainer (COMPLETED)
```bash
# ALREADY APPLIED - file renamed and application name updated
# File: apps/kubeflow/trainer.yaml (was training.yaml)
```

### ✅ Fix 4: Sync Wave Annotations (COMPLETED)
All 9 existing applications now have sync wave annotations for proper deployment ordering:
- Wave 0: common-services
- Wave 2: kubeflow-pipelines, katib, jupyter
- Wave 3: kserve, trainer
- Wave 4: web-apps
- Wave 5: spark, model-registry

---

## 📋 Remaining Work

### Phase 1: Complete Missing Components (2-3 hours remaining)

**✅ Phase 1a: Critical Path Fixes** - COMPLETED
- Fixed web-apps namespace
- Fixed model-registry path
- Renamed training to trainer
- Added sync wave annotations to all 9 apps

**→ Phase 1b: Create Missing Applications** - IN PROGRESS

#### Step 1: Create Common Services Kustomization
```bash
mkdir -p apps/base/common-services
```

Create `apps/base/common-services/kustomization.yaml`:
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
# Cert-Manager
- ../../../../common/cert-manager/base
- ../../../../common/cert-manager/kubeflow-issuer/base

# Istio
- ../../../../common/istio/istio-crds/base
- ../../../../common/istio/istio-namespace/base
- ../../../../common/istio/istio-install/overlays/oauth2-proxy

# OAuth2-Proxy & Dex
- ../../../../common/oauth2-proxy/overlays/m2m-dex-only
- ../../../../common/dex/overlays/oauth2-proxy

# Knative
- ../../../../common/knative/knative-serving/overlays/gateways
- ../../../../common/istio/cluster-local-gateway/base

# Kubeflow Core
- ../../../../common/kubeflow-namespace/base
- ../../../../common/networkpolicies/base
- ../../../../common/kubeflow-roles/base
- ../../../../common/istio/kubeflow-istio-resources/base
```

Then update `apps/kubeflow/common-services.yaml`:
```yaml
spec:
  source:
    path: bootstrap/apps/base/common-services
```

#### Step 2: Create Missing Applications

**profiles.yaml**:
```bash
cat > apps/kubeflow/profiles.yaml <<'EOF'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: kubeflow-profiles
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "1"
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://github.com/minhhcuongg-theonefour/k8s-inspect.git
    targetRevision: feat/sync-wave
    path: applications/profiles/pss
  destination:
    server: https://kubernetes.default.svc
    namespace: kubeflow
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
EOF
```

**admission-webhook.yaml**:
```bash
cat > apps/kubeflow/admission-webhook.yaml <<'EOF'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: kubeflow-admission-webhook
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "1"
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://github.com/minhhcuongg-theonefour/k8s-inspect.git
    targetRevision: feat/sync-wave
    path: applications/admission-webhook/upstream/overlays/cert-manager
  destination:
    server: https://kubernetes.default.svc
    namespace: kubeflow
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
EOF
```

**pvcviewer-controller.yaml**:
```bash
cat > apps/kubeflow/pvcviewer-controller.yaml <<'EOF'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: kubeflow-pvcviewer-controller
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "4"
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://github.com/minhhcuongg-theonefour/k8s-inspect.git
    targetRevision: feat/sync-wave
    path: applications/pvcviewer-controller/upstream/base
  destination:
    server: https://kubernetes.default.svc
    namespace: kubeflow
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
EOF
```

**user-namespace.yaml**:
```bash
cat > apps/kubeflow/user-namespace.yaml <<'EOF'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: kubeflow-user-namespace
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "5"
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://github.com/minhhcuongg-theonefour/k8s-inspect.git
    targetRevision: feat/sync-wave
    path: common/user-namespace/base
  destination:
    server: https://kubernetes.default.svc
    namespace: kubeflow
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
EOF
```

#### ✅ Step 3: Add Sync Wave Annotations - COMPLETED

All existing applications now have sync wave annotations. No action needed.

### Phase 2: Create App of Apps (1 hour)

#### 2.1 Create Apps Kustomization

Create `apps/kubeflow/kustomization.yaml`:
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
# Wave 0: Foundation
- common-services.yaml

# Wave 1: Core
- profiles.yaml
- admission-webhook.yaml

# Wave 2: ML Platform
- kubeflow-pipelines.yaml
- katib.yaml
- jupyter.yaml

# Wave 3: Serving & Training
- kserve.yaml
- trainer.yaml

# Wave 4: Web Apps
- web-apps.yaml
- pvcviewer-controller.yaml

# Wave 5: Additional
- spark.yaml
- model-registry.yaml
- user-namespace.yaml
```

#### 2.2 Create Root Application

Create `app-of-apps.yaml`:
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: kubeflow-app-of-apps
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://github.com/minhhcuongg-theonefour/k8s-inspect.git
    targetRevision: feat/sync-wave
    path: bootstrap/apps/kubeflow
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
```

---

## 📊 Progress Summary

### What We've Accomplished ✅

1. **Fixed Configuration Errors** (3/3 completed)
   - ✅ Web apps namespace corrected (`istio-system` → `kubeflow`)
   - ✅ Model registry path fixed to include database (`base` → `overlays/db`)
   - ✅ Training/Trainer naming clarified and file renamed

2. **Added Deployment Orchestration** (9/9 apps)
   - ✅ Sync wave annotations added to all existing applications
   - ✅ Deployment order defined (Wave 0 → Wave 5)
   - ✅ Race conditions and dependency issues prevented

3. **Documentation Updated**
   - ✅ Current status clearly documented
   - ✅ Sync wave strategy explained
   - ✅ Previous issues and their causes documented

### What Still Needs To Be Done ⚠️

1. **Create Missing Applications** (0/4 completed)
   - ⚠️ profiles.yaml (Wave 1) - User management
   - ⚠️ admission-webhook.yaml (Wave 1) - PodDefaults support
   - ⚠️ pvcviewer-controller.yaml (Wave 4) - PVC UI
   - ⚠️ user-namespace.yaml (Wave 5) - Default user

2. **Fix Infrastructure Path** (0/1 completed)
   - ⚠️ Create common-services kustomization
   - ⚠️ Update common-services.yaml to use correct path

3. **Create Orchestration** (0/2 completed)
   - ⚠️ Create apps/kubeflow/kustomization.yaml
   - ⚠️ Create app-of-apps.yaml for centralized management

### Current Readiness Level

| Component | Status | Ready for Deployment |
|-----------|--------|---------------------|
| Existing Apps (9) | ✅ Configured | Yes (with caveats) |
| Sync Waves | ✅ Implemented | Yes |
| Infrastructure | ⚠️ Path Incorrect | No - needs fix first |
| Core Components | ❌ Missing | No - need to create |
| **Overall** | **⚠️ 64% Complete** | **Partial - existing apps only** |

**Recommendation**: Complete Phase 1b and Phase 2 before deploying to production.

---

## 🚀 Deployment

### Prerequisites

1. **Kubernetes Cluster** (v1.27+)
   - 8+ CPU cores
   - 32+ GB RAM
   - 100+ GB storage

2. **kubectl** configured and connected

3. **Git Repository** accessible

### Step-by-Step Deployment

#### 1. Install ArgoCD
```bash
make install-argocd
```

Wait for ArgoCD to be ready:
```bash
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=300s
```

#### 2. Get ArgoCD Password
```bash
make get-argocd-password
```

#### 3. Access ArgoCD UI (Optional)
```bash
make port-forward-argocd
# Visit: http://localhost:8080
# Username: admin
# Password: (from step 2)
```

#### 4. Deploy App of Apps
```bash
make deploy-app-of-apps
```

#### 5. Monitor Deployment
```bash
# Watch applications
make watch-apps

# Check status
make status

# View logs
make logs APP=kubeflow-pipelines
```

#### 6. Verify Deployment
```bash
make verify
```

---

## 📖 Makefile Commands

### Installation Commands
```bash
make install-argocd          # Install ArgoCD in cluster
make install-argocd-cli      # Install ArgoCD CLI locally (macOS)
```

### Deployment Commands
```bash
make deploy-argocd           # Deploy ArgoCD application
make deploy-bootstrap        # Deploy bootstrap application
make deploy-app-of-apps      # Deploy app-of-apps pattern (RECOMMENDED)
make deploy-all              # Deploy everything
```

### Management Commands
```bash
make status                  # Show status of all applications
make watch-apps              # Watch applications in real-time
make sync-all                # Sync all applications
make refresh-all             # Refresh all applications
```

### Access Commands
```bash
make get-argocd-password     # Get ArgoCD admin password
make port-forward-argocd     # Port forward to ArgoCD UI (8080)
```

### Troubleshooting Commands
```bash
make logs APP=<name>         # View logs for specific application
make describe APP=<name>     # Describe application
make diff APP=<name>         # Show diff for application
```

### Validation Commands
```bash
make validate                # Validate all manifests
make verify                  # Verify deployment
make test                    # Run tests
```

### Cleanup Commands
```bash
make delete-app APP=<name>   # Delete specific application
make delete-all-apps         # Delete all Kubeflow applications
make uninstall-argocd        # Uninstall ArgoCD
make clean                   # Clean everything
```

### Utility Commands
```bash
make help                    # Show all available commands
make update-repo-url REPO=<url> # Update repository URL
```

---

## 🔍 Sync Wave Strategy

Applications deploy in this order:

```
Wave 0 (Foundation - ~2 min):
  └─ common-services
     ├─ Cert-Manager
     ├─ Istio (CRDs, namespace, install)
     ├─ Dex
     ├─ OAuth2-Proxy
     └─ Knative

Wave 1 (Core - ~1 min):
  ├─ profiles
  └─ admission-webhook

Wave 2 (ML Platform - ~2 min):
  ├─ kubeflow-pipelines
  ├─ katib
  └─ jupyter

Wave 3 (Serving & Training - ~1 min):
  ├─ kserve
  └─ trainer

Wave 4 (Web Apps - ~1 min):
  ├─ web-apps
  └─ pvcviewer-controller

Wave 5 (Additional - ~1 min):
  ├─ spark
  ├─ model-registry
  └─ user-namespace

Total Deployment Time: ~8-10 minutes
```

---

## 🔧 SSL/Port-Forward Access Fix

### Problem: "No Healthy Upstream" Error
When accessing Kubeflow dashboard via port-forward, you may encounter SSL/TLS errors or "no healthy upstream" messages.

### Root Cause
Web application pods fail to start due to Pod Security Standards (PSS) violations in the `kubeflow` namespace.

### Solution
```bash
# 1. Fix Pod Security Standards (change from 'restricted' to 'baseline')
kubectl patch namespace kubeflow -p '{"metadata":{"labels":{"pod-security.kubernetes.io/enforce":"baseline"}}}'

# 2. Restart failed web application deployments
kubectl rollout restart deployment centraldashboard -n kubeflow
kubectl rollout restart deployment jupyter-web-app-deployment -n kubeflow
kubectl rollout restart deployment volumes-web-app-deployment -n kubeflow
kubectl rollout restart deployment tensorboards-web-app-deployment -n kubeflow

# 3. Verify pods are running
kubectl get pods -n kubeflow | grep -E "(centraldashboard|web-app)"

# 4. Access dashboard without SSL issues
kubectl port-forward svc/istio-ingressgateway -n istio-system 8080:80
# Visit: http://localhost:8080 (no SSL required)
```

### Result
- ✅ Dashboard pods start successfully
- ✅ Port-forward works without SSL/TLS errors
- ✅ All Kubeflow web UIs accessible via HTTP

---

## 🛠️ Troubleshooting

### Application Stuck in Progressing
```bash
# Refresh application
make refresh APP=<app-name>

# Force sync
argocd app sync <app-name> --force
```

### Webhook Certificate Errors
```bash
# Delete certificates
kubectl delete certificate --all -n kubeflow

# Resync cert-manager
argocd app sync kubeflow-common-services --force
```

### CRD Not Found Errors
```bash
# Ensure wave 0 is complete
argocd app wait kubeflow-common-services

# Then sync next wave
argocd app sync kubeflow-profiles
```

### Out of Sync
```bash
# Hard refresh
argocd app get <app-name> --hard-refresh

# Sync with replace
argocd app sync <app-name> --replace
```

---

## 📊 Verification Checklist

After deployment, verify:

- [ ] All ArgoCD applications show "Healthy" status
- [ ] All pods are in "Running" state
- [ ] No CrashLoopBackOff errors
- [ ] Can access Kubeflow dashboard
- [ ] Can authenticate via Dex
- [ ] Can create user profiles
- [ ] Can launch notebooks
- [ ] Can run pipelines
- [ ] Can deploy models

```bash
# Quick verification
make verify
```

---

## 🔄 Updating Repository URL

To update the Git repository URL in all manifests:

```bash
make update-repo-url REPO=https://github.com/your-org/your-repo
```

Or manually:
```bash
./update-repo-urls.sh https://github.com/your-org/your-repo main
```

---

## 📚 Additional Resources

- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [Kubeflow Documentation](https://www.kubeflow.org/docs/)
- [App of Apps Pattern](https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/)

---

## 🤝 Contributing

When adding new applications:

1. Create application manifest in `apps/kubeflow/`
2. Add appropriate sync wave annotation
3. Add to `apps/kubeflow/kustomization.yaml`
4. Test on development cluster first
5. Update this README

---

## 📝 Notes

- **Repository**: https://github.com/minhhcuongg-theonefour/k8s-inspect
- **Branch**: feat/sync-wave
- **ArgoCD Version**: 8.5.9
- **Last Updated**: 2025-10-09
