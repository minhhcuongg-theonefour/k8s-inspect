# Kubeflow Profile Examples

This directory contains example configurations for creating Kubeflow profiles with authentication.

## Prerequisites Check

Before creating profiles, run the prerequisites check:

```bash
./check-prerequisites.sh
```

This will verify:
- ✅ kubectl is installed and connected
- ✅ Profile CRD is installed
- ✅ Profile controller is running
- ✅ Dex is configured and running
- ✅ OAuth2-Proxy is deployed
- ✅ Istio is ready
- ✅ Python with passlib is available

## Quick Start

### 1. Add Users to Dex

Generate password hashes:
```bash
# Generate hash for each user
python3 -c 'from passlib.hash import bcrypt; import getpass; print(bcrypt.using(rounds=12, ident="2y").hash(getpass.getpass()))'
```

Update Dex configuration:
```bash
# Copy example and modify
cp add-multiple-users-dex.yaml ../../common/dex/overlays/oauth2-proxy/config-map.yaml
cp dex-passwords-example.yaml ../../common/dex/base/dex-passwords.yaml

# Edit and add your password hashes
vim ../../common/dex/base/dex-passwords.yaml

# Apply changes
kustomize build ../../common/dex/overlays/oauth2-proxy | kubectl apply -f -
kubectl rollout restart deployment dex -n auth
```

### 2. Create Profiles

Choose an example based on your needs:

#### Basic Profile (No Quotas)
```bash
# Edit email to match user in Dex
vim basic-profile.yaml
kubectl apply -f basic-profile.yaml
```

#### Profile with Resource Quotas
```bash
# Edit email and adjust quotas
vim profile-with-quotas.yaml
kubectl apply -f profile-with-quotas.yaml
```

#### Team Profile with Multiple Users
```bash
# Edit emails for team lead and members
vim team-profile.yaml
kubectl apply -f team-profile.yaml
```

### 3. Verify

```bash
# List profiles
kubectl get profiles

# Check specific profile
kubectl describe profile <profile-name>

# Verify namespace created
kubectl get namespaces | grep <profile-name>

# Check resource quotas
kubectl get resourcequota -n <profile-name>
```

### 4. Test Login

```bash
# Port-forward Istio gateway
kubectl port-forward svc/istio-ingressgateway -n istio-system 8080:80

# Open browser to http://localhost:8080
# Login with user email and password
```

## Examples Included

| File | Description | Use Case |
|------|-------------|----------|
| `basic-profile.yaml` | Simple profile with no resource limits | Quick testing, unlimited resources |
| `profile-with-quotas.yaml` | Profile with CPU, memory, GPU, storage quotas | Individual user with resource constraints |
| `team-profile.yaml` | Shared profile for multiple users | Team collaboration workspace |
| `add-multiple-users-dex.yaml` | Dex ConfigMap with multiple static users | Adding multiple users to authentication |
| `dex-passwords-example.yaml` | Password secret template | Storing user password hashes |

## Profile Fields Explained

```yaml
apiVersion: kubeflow.org/v1
kind: Profile
metadata:
  name: my-profile          # Becomes the namespace name
spec:
  owner:
    kind: User
    name: user@example.com  # MUST match email from Dex
  resourceQuotaSpec:        # Optional: resource limits
    hard:
      cpu: "4"                              # Total CPU cores
      memory: 8Gi                           # Total memory
      requests.nvidia.com/gpu: "2"          # GPU count
      persistentvolumeclaims: "5"           # Max PVC count
      requests.storage: "50Gi"              # Total storage
      pods: "50"                            # Max pods
```

## Resource Quota Guidelines

### Small User Profile (Development)
- CPU: 2 cores
- Memory: 4Gi
- GPU: 0-1
- Storage: 20Gi
- PVCs: 3

### Medium User Profile (Active ML Work)
- CPU: 4-8 cores
- Memory: 8-16Gi
- GPU: 1-2
- Storage: 50Gi
- PVCs: 5

### Large Team Profile (Production)
- CPU: 16+ cores
- Memory: 32+ Gi
- GPU: 4+
- Storage: 200+ Gi
- PVCs: 20+

## Access Control Roles

Grant users access to profiles using ClusterRoles:

| Role | Permissions | Use Case |
|------|-------------|----------|
| `kubeflow-view` | Read-only access | Auditors, observers |
| `kubeflow-edit` | Create/modify resources | Regular users, developers |
| `kubeflow-admin` | Full control including RBAC | Administrators, team leads |

Example:
```bash
kubectl create rolebinding user-access \
  --clusterrole=kubeflow-edit \
  --user=user@example.com \
  --namespace=profile-namespace
```

## Troubleshooting

For detailed troubleshooting, see [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

### Quick Diagnostics

```bash
# Run full system check
./check-prerequisites.sh

# Check specific issues
kubectl logs -n kubeflow deployment/profiles-deployment  # Profile controller
kubectl logs -n auth deployment/dex                       # Authentication
kubectl describe profile <profile-name>                   # Profile status
```

### Common Issues

| Issue | Quick Fix | Details |
|-------|-----------|---------|
| Profile CRD not found | Install: `kustomize build applications/profiles/upstream/overlays/kubeflow \| kubectl apply -f -` | [TROUBLESHOOTING.md](TROUBLESHOOTING.md#1-profile-crd-not-found) |
| Email mismatch | Ensure Dex email = Profile email (exact match) | [TROUBLESHOOTING.md](TROUBLESHOOTING.md#2-user-can-login-but-sees-no-profiles-available) |
| Cannot login | Regenerate password hash and update secret | [TROUBLESHOOTING.md](TROUBLESHOOTING.md#5-invalid-password-or-cannot-login) |
| Resource quota | Check: `kubectl describe resourcequota -n <namespace>` | [TROUBLESHOOTING.md](TROUBLESHOOTING.md#6-resource-quota-exceeded) |

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for comprehensive troubleshooting guide.

## Additional Resources

- [Full Profile Creation Guide](../../PROFILE_CREATION_GUIDE.md)
- [Main README](../../README.md)
- [Dex Integration Guide](../../common/dex/README.md)
- [Kubeflow Multi-User Documentation](https://www.kubeflow.org/docs/components/multi-tenancy/)
