# Solution for Your Error

## The Problem You Encountered

```
error: resource mapping not found for name: "alice-profile" namespace: ""
from "/tmp/profile_alice.yaml": no matches for kind "Profile" in version "kubeflow.org/v1"
ensure CRDs are installed first
```

## Root Cause

The **Profile Custom Resource Definition (CRD)** is not installed in your cluster. This means Kubernetes doesn't recognize "Profile" as a valid resource type.

## Solution

### Step 1: Check Prerequisites

First, run the diagnostic script to see what's missing:

```bash
cd /home/thomas/work/mlops_infra/kubeflow-pack/manifests/examples/profiles
./check-prerequisites.sh
```

This will tell you exactly what components are missing.

### Step 2: Install Missing Components

Based on the error, you need to install the Profiles component (and possibly other Kubeflow components).

#### Option A: Install Full Kubeflow (Recommended)

If you want the complete Kubeflow installation:

```bash
cd /home/thomas/work/mlops_infra/kubeflow-pack/manifests

# This installs everything including profiles
while ! kustomize build example | kubectl apply --server-side --force-conflicts -f -; do
  echo "Retrying to apply resources";
  sleep 20;
done
```

Wait for all components to be ready (this can take 5-15 minutes):
```bash
# Check all Kubeflow namespaces
kubectl get pods -n kubeflow
kubectl get pods -n auth
kubectl get pods -n oauth2-proxy
kubectl get pods -n istio-system
```

#### Option B: Install Just Profiles Component

If you only want to install the profiles component:

```bash
cd /home/thomas/work/mlops_infra/kubeflow-pack/manifests

# Install Profile CRD and controller
kustomize build applications/profiles/upstream/overlays/kubeflow | kubectl apply -f -

# Wait for profile controller to be ready
kubectl wait --for=condition=Ready pods -l app=profiles -n kubeflow --timeout=180s
```

### Step 3: Verify Installation

Check that the Profile CRD is now installed:

```bash
kubectl get crd profiles.kubeflow.org
```

Expected output:
```
NAME                       CREATED AT
profiles.kubeflow.org      2025-10-16T...
```

Check API versions:
```bash
kubectl api-resources | grep profile
```

Expected output:
```
profiles      kubeflow.org/v1    false    Profile
```

### Step 4: Retry Profile Creation

Now try creating the profile again:

```bash
cd /home/thomas/work/mlops_infra/kubeflow-pack/manifests/examples/profiles

# Either use the script
./create-user-and-profile.sh alice@example.com alice alice-profile

# Or manually apply the profile
cat <<EOF | kubectl apply -f -
apiVersion: kubeflow.org/v1
kind: Profile
metadata:
  name: alice-profile
spec:
  owner:
    kind: User
    name: alice@example.com
EOF
```

### Step 5: Verify Profile Creation

```bash
# Check profile exists
kubectl get profile alice-profile

# Check namespace was created
kubectl get namespace alice-profile

# Check detailed status
kubectl describe profile alice-profile
```

## What Happened

The script you ran (`create-user-and-profile.sh`) successfully:
1. ✅ Generated password hash
2. ✅ Updated Dex configuration (you manually added the user)
3. ✅ Updated Dex secrets
4. ✅ Restarted Dex

But failed at:
5. ❌ Creating the Profile - because the Profile CRD wasn't installed

## Full Installation Order

For future reference, here's the correct order for a complete setup:

1. **Install Kubernetes Infrastructure**
   - Cert-manager
   - Istio
   - Knative (for KServe)

2. **Install Authentication**
   - Dex
   - OAuth2-Proxy

3. **Install Kubeflow Core**
   - Kubeflow namespace
   - Kubeflow roles
   - Profile controller ← **This is what you were missing**

4. **Install Kubeflow Applications**
   - Pipelines
   - Notebooks
   - KServe
   - Katib
   - etc.

5. **Create User Profiles**
   - Add users to Dex
   - Create Profile resources

## Quick Commands Summary

```bash
# 1. Check what's missing
cd /home/thomas/work/mlops_infra/kubeflow-pack/manifests/examples/profiles
./check-prerequisites.sh

# 2. Install full Kubeflow (or just profiles component)
cd /home/thomas/work/mlops_infra/kubeflow-pack/manifests
while ! kustomize build example | kubectl apply --server-side --force-conflicts -f -; do
  sleep 20;
done

# 3. Wait for everything to be ready
kubectl get pods -n kubeflow --watch

# 4. Verify Profile CRD
kubectl get crd profiles.kubeflow.org

# 5. Create profile
cd /home/thomas/work/mlops_infra/kubeflow-pack/manifests/examples/profiles
./create-user-and-profile.sh alice@example.com alice alice-profile
```

## Next Steps After Installation

Once everything is installed:

1. **Test the profile creation script again**
2. **Port-forward the gateway**:
   ```bash
   kubectl port-forward svc/istio-ingressgateway -n istio-system 8080:80
   ```
3. **Open browser to http://localhost:8080**
4. **Login with**: alice@example.com / (your password)

## Helpful Resources

- **Prerequisites Check**: `./check-prerequisites.sh`
- **Troubleshooting Guide**: [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
- **Quick Start**: [QUICK_START.md](QUICK_START.md)
- **Full Guide**: [../../PROFILE_CREATION_GUIDE.md](../../PROFILE_CREATION_GUIDE.md)
- **Main README**: [../../README.md](../../README.md)

## Need More Help?

If you still encounter issues after following these steps:

1. Run: `./check-prerequisites.sh` and share the output
2. Check logs: `kubectl logs -n kubeflow deployment/profiles-deployment`
3. See: [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for detailed solutions
