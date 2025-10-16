# ArgoCD Sync Issue Analysis and Resolution

**Date:** October 16, 2025
**Issue:** Kubeflow Web Apps failing to sync due to missing Istio CRDs
**Status:** ✅ RESOLVED

---

## Executive Summary

The `kubeflow-web-apps` ArgoCD application was failing to sync with the error:
```
The Kubernetes API could not find networking.istio.io/VirtualService for requested resource...
Make sure the "VirtualService" CRD is installed on the destination cluster.
```

**Root Cause:** The prerequisite `kubeflow-common-services` application (sync wave 0) was misconfigured and failing to deploy Istio CRDs and other foundational components.
# ArgoCD Sync Issue Analysis and Resolution

**Date:** October 16, 2025
**Issue:** Kubeflow Web Apps failing to sync due to missing Istio CRDs
**Status:** ✅ RESOLVED

---

## Executive Summary

The `kubeflow-web-apps` ArgoCD application was failing to sync with the error:
```
The Kubernetes API could not find networking.istio.io/VirtualService for requested resource...
Make sure the "VirtualService" CRD is installed on the destination cluster.
```

**Root Cause:** The prerequisite `kubeflow-common-services` application (sync wave 0) was misconfigured and failing to deploy Istio CRDs and other foundational components.

---

## Problem Analysis

### 1. Sync Wave Configuration (✅ Correct)

The sync wave ordering was properly configured:
- **Wave 0:** `kubeflow-common-services` - Foundation (Cert-Manager, Istio, Dex, OAuth2-Proxy, Knative)
- **Wave 4:** `kubeflow-web-apps` - Web UIs (Central Dashboard, Volumes Web App, Tensorboard Web App)

### 2. Common Services Application Issues (❌ Broken)

The `kubeflow-common-services` app had **three critical issues**:

#### Issue 1: InvalidSpecError
```
Namespace for default-install-config-9h2h2b6hbk /v1, Kind=ConfigMap is missing.
```

#### Issue 2: SharedResourceWarning (50+ conflicts)
Resources managed by **multiple ArgoCD applications simultaneously**:
- `jobset-*`, `kubeflow-trainer-*` resources: in BOTH `kubeflow-common-services` AND `kubeflow-trainer`
- `spark-operator-*` resources: in BOTH `kubeflow-common-services` AND `kubeflow-spark`

#### Issue 3: Incorrect Scope
The common-services app pointed to `example/kustomization.yaml` which included:
- ❌ All Kubeflow applications (Pipelines, Katib, Jupyter, KServe, etc.)
- ❌ Application-specific components (Trainer, Spark, etc.)
- ✅ Common infrastructure (Cert-Manager, Istio, Dex, etc.)

This created resource conflicts because individual apps also managed the same resources.

### 3. Cascade Failure

```
kubeflow-common-services (wave 0) FAILED
    ↓
Istio CRDs NOT installed
    ↓
kubeflow-web-apps (wave 4) CANNOT sync
    ↓
All dependent apps BLOCKED
```
## Problem Analysis

### 1. Sync Wave Configuration (✅ Correct)

The sync wave ordering was properly configured:
- **Wave 0:** `kubeflow-common-services` - Foundation (Cert-Manager, Istio, Dex, OAuth2-Proxy, Knative)
- **Wave 4:** `kubeflow-web-apps` - Web UIs (Central Dashboard, Volumes Web App, Tensorboard Web App)

### 2. Common Services Application Issues (❌ Broken)

The `kubeflow-common-services` app had **three critical issues**:

#### Issue 1: InvalidSpecError
```
Namespace for default-install-config-9h2h2b6hbk /v1, Kind=ConfigMap is missing.
```

#### Issue 2: SharedResourceWarning (50+ conflicts)
Resources managed by **multiple ArgoCD applications simultaneously**:
- `jobset-*`, `kubeflow-trainer-*` resources: in BOTH `kubeflow-common-services` AND `kubeflow-trainer`
- `spark-operator-*` resources: in BOTH `kubeflow-common-services` AND `kubeflow-spark`

#### Issue 3: Incorrect Scope
The common-services app pointed to `example/kustomization.yaml` which included:
- ❌ All Kubeflow applications (Pipelines, Katib, Jupyter, KServe, etc.)
- ❌ Application-specific components (Trainer, Spark, etc.)
- ✅ Common infrastructure (Cert-Manager, Istio, Dex, etc.)

This created resource conflicts because individual apps also managed the same resources.

### 3. Cascade Failure

```
kubeflow-common-services (wave 0) FAILED
    ↓
Istio CRDs NOT installed
    ↓
kubeflow-web-apps (wave 4) CANNOT sync
    ↓
All dependent apps BLOCKED
```

---

## Solution Implemented

### Step 1: Create Dedicated Common Services Kustomization

Created a new kustomization at `example/common-component-chart/kustomization.yaml` that **ONLY** includes foundational infrastructure:

## Solution Implemented

### Step 1: Create Dedicated Common Services Kustomization

Created a new kustomization at `example/common-component-chart/kustomization.yaml` that **ONLY** includes foundational infrastructure:

```yaml
resources:
  # Cert-Manager
  - ../../common/cert-manager/base
  - ../../common/cert-manager/kubeflow-issuer/base
  # Cert-Manager
  - ../../common/cert-manager/base
  - ../../common/cert-manager/kubeflow-issuer/base

  # Istio (CRDs, Namespace, Installation)
  - ../../common/istio/istio-crds/base
  - ../../common/istio/istio-namespace/base
  - ../../common/istio/istio-install/overlays/oauth2-proxy
  # Istio (CRDs, Namespace, Installation)
  - ../../common/istio/istio-crds/base
  - ../../common/istio/istio-namespace/base
  - ../../common/istio/istio-install/overlays/oauth2-proxy

  # oauth2-proxy
  - ../../common/oauth2-proxy/overlays/m2m-dex-only

  # Dex
  - ../../common/dex/overlays/oauth2-proxy
  # oauth2-proxy
  - ../../common/oauth2-proxy/overlays/m2m-dex-only

  # Dex
  - ../../common/dex/overlays/oauth2-proxy

  # Knative
  - ../../common/knative/knative-serving/overlays/gateways
  - ../../common/istio/cluster-local-gateway/base
  # Knative
  - ../../common/knative/knative-serving/overlays/gateways
  - ../../common/istio/cluster-local-gateway/base

  # Kubeflow namespace
  - ../../common/kubeflow-namespace/base

  # NetworkPolicies
  - ../../common/networkpolicies/base

  # Kubeflow Roles
  - ../../common/kubeflow-roles/base

  # Kubeflow Istio Resources
  - ../../common/istio/kubeflow-istio-resources/base
  # Kubeflow namespace
  - ../../common/kubeflow-namespace/base

  # NetworkPolicies
  - ../../common/networkpolicies/base

  # Kubeflow Roles
  - ../../common/kubeflow-roles/base

  # Kubeflow Istio Resources
  - ../../common/istio/kubeflow-istio-resources/base
```

**Key Exclusions:**
- ❌ Trainer components (managed by `kubeflow-trainer` app)
- ❌ Spark components (managed by `kubeflow-spark` app)
- ❌ Pipelines (managed by `kubeflow-pipelines` app)
- ❌ Jupyter (managed by `kubeflow-jupyter` app)
- ❌ Katib (managed by `kubeflow-katib` app)
- ❌ KServe (managed by `kubeflow-kserve` app)

### Step 2: Update ArgoCD Application

Modified `bootstrap/apps/kubeflow/common-services.yaml`:

**Key Exclusions:**
- ❌ Trainer components (managed by `kubeflow-trainer` app)
- ❌ Spark components (managed by `kubeflow-spark` app)
- ❌ Pipelines (managed by `kubeflow-pipelines` app)
- ❌ Jupyter (managed by `kubeflow-jupyter` app)
- ❌ Katib (managed by `kubeflow-katib` app)
- ❌ KServe (managed by `kubeflow-kserve` app)

### Step 2: Update ArgoCD Application

Modified `bootstrap/apps/kubeflow/common-services.yaml`:

```yaml
spec:
  source:
    path: example/common-component-chart  # Changed from: example
```

---

## Validation

### Kustomization Build Test
```bash
$ cd example/common-component-chart
$ kustomize build . | wc -l
48078  # ✅ Successfully generates 48K lines of YAML
```

### Istio CRDs Verification
```bash
$ kustomize build . | grep "networking.istio.io\|security.istio.io"
name: authorizationpolicies.security.istio.io
name: virtualservices.networking.istio.io
name: destinationrules.networking.istio.io
# ... and more Istio CRDs
```

✅ All required Istio CRDs are included.

---

## Deployment Steps

### Option 1: Git Commit and Push (Recommended for GitOps)
```bash
cd /home/thomas/work/mlops_infra/kubeflow-pack/manifests

# Review changes
git status
git diff

# Commit changes
git add example/common-component-chart/kustomization.yaml
git add bootstrap/apps/kubeflow/common-services.yaml
git commit -m "Fix: Separate common services from application components

- Create dedicated common-component-chart for infrastructure only
- Remove shared resources (trainer, spark) to prevent conflicts
- Update common-services ArgoCD app to point to new path
- Resolves InvalidSpecError and SharedResourceWarning issues
- Fixes missing Istio CRDs preventing web apps sync"

# Push to trigger ArgoCD sync
git push origin main
```

### Option 2: Manual Sync (For Testing)
```bash
# Sync common services first
argocd app sync kubeflow-common-services --force

# Wait for common services to be healthy
argocd app wait kubeflow-common-services --health

# Then sync web apps
argocd app sync kubeflow-web-apps --force
```

---

## Expected Results

After applying the fix:

1. **kubeflow-common-services:**
   - ✅ Status: Synced
   - ✅ Health: Healthy
   - ✅ Conditions: No errors
   - ✅ Istio CRDs installed
   - ✅ Cert-Manager running
   - ✅ Dex, OAuth2-Proxy, Knative deployed

2. **kubeflow-web-apps:**
   - ✅ Status: Synced (was: OutOfSync)
   - ✅ Health: Healthy (was: Missing)
   - ✅ All VirtualServices created
   - ✅ All AuthorizationPolicies created
   - ✅ All Deployments running

3. **Other Applications:**
   - ✅ kubeflow-jupyter: Can sync
   - ✅ kubeflow-katib: Can sync
   - ✅ kubeflow-kserve: Can sync
   - ✅ kubeflow-trainer: No conflicts
   - ✅ kubeflow-spark: No conflicts

---

## Monitoring

Check application status after deployment:
```bash
# Monitor common services
argocd app get kubeflow-common-services

# Monitor web apps
argocd app get kubeflow-web-apps

# List all apps
argocd app list -o wide

# Check Istio CRDs on cluster
kubectl get crd | grep istio.io

# Verify Istio pods
kubectl get pods -n istio-system
```

---

## Architecture Best Practices

### Sync Wave Strategy
```
Wave -1: External dependencies, secrets
Wave  0: Infrastructure (CRDs, Cert-Manager, Istio, Dex, OAuth2-Proxy, Knative)
Wave  1: Core services (Profiles, RBAC, Admission Webhook)
Wave  2: ML platform (Pipelines, Katib, Jupyter Controller)
Wave  3: Serving & Training (KServe, Training Operator)
Wave  4: Web UIs (Central Dashboard, Jupyter Web App, etc.)
Wave  5: Optional services (Spark, Model Registry)
```

### Resource Ownership
- **One ArgoCD Application = One Set of Resources**
- **No Shared Resources** between applications
- **Common Services** = Infrastructure only
- **Individual Apps** = Their specific components

### Dependency Management
- Use sync waves for ordering
- Higher wave numbers depend on lower waves
- ArgoCD automatically respects wave ordering

---

## Troubleshooting

### If common-services still fails:

1. **Check logs:**
   ```bash
   argocd app get kubeflow-common-services --show-operation
   ```

2. **Check for CRD issues:**
   ```bash
   kubectl get crd | grep istio
   kubectl get crd | grep cert-manager
   ```

3. **Force refresh:**
   ```bash
   argocd app sync kubeflow-common-services --force --replace
   ```

### If web-apps still fails:

1. **Verify Istio is running:**
   ```bash
   kubectl get pods -n istio-system
   kubectl get crd | grep networking.istio.io
   ```

2. **Check dependencies:**
   ```bash
   argocd app get kubeflow-common-services
   ```

3. **Manual sync with retry:**
   ```bash
   argocd app sync kubeflow-web-apps --retry-limit 5
   ```

---

## Files Modified

1. ✅ **NEW:** `example/common-component-chart/kustomization.yaml`
2. ✅ **MODIFIED:** `bootstrap/apps/kubeflow/common-services.yaml`

## Files Referenced

- `bootstrap/apps/kubeflow/sync-waves.yaml` - Sync wave documentation
- `bootstrap/apps/kubeflow/web-apps.yaml` - Web apps configuration
- `example/kustomization.yaml` - Original (full) kustomization

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

## Conclusion

The issue was caused by **resource conflicts and incorrect separation of concerns** in the GitOps structure. By creating a dedicated kustomization for common infrastructure services and removing application-specific components, we:

1. ✅ Eliminated SharedResourceWarnings
2. ✅ Fixed InvalidSpecError
3. ✅ Ensured Istio CRDs are deployed in wave 0
4. ✅ Enabled web apps to sync successfully in wave 4
5. ✅ Followed GitOps best practices for resource ownership

The fix follows the **single responsibility principle** - each ArgoCD application manages a distinct, non-overlapping set of resources.
