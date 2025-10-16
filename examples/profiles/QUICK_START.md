# Quick Start: Creating Kubeflow Profiles with Authentication

This quick start guide will help you create Kubeflow profiles with managed login control in under 10 minutes.

## Prerequisites

- Kubeflow installed and running
- `kubectl` configured and connected to your cluster
- Python 3 with `passlib` installed: `pip install passlib`

## 3-Step Quick Start

### Step 1: Add User to Dex (Authentication)

```bash
# Generate password hash
python3 -c 'from passlib.hash import bcrypt; import getpass; print(bcrypt.using(rounds=12, ident="2y").hash(getpass.getpass()))'
# Enter your password when prompted
# Copy the hash output (starts with $2y$12$...)
```

Add user to Dex ConfigMap:
```bash
kubectl edit configmap dex -n auth
```

Add this under `staticPasswords`:
```yaml
    - email: alice@example.com
      hashFromEnv: DEX_ALICE_PASSWORD
      username: alice
      userID: "15841185641785"
```

Update password secret:
```bash
# Replace <HASH> with the hash you generated above
kubectl patch secret dex-passwords -n auth --type merge \
  -p '{"stringData":{"DEX_ALICE_PASSWORD":"<HASH>"}}'

# Restart Dex
kubectl rollout restart deployment dex -n auth
kubectl wait --for=condition=Ready pods -l app=dex -n auth --timeout=180s
```

### Step 2: Create Profile

```bash
cat <<EOF | kubectl apply -f -
apiVersion: kubeflow.org/v1
kind: Profile
metadata:
  name: alice-profile
spec:
  owner:
    kind: User
    name: alice@example.com
  resourceQuotaSpec:
    hard:
      cpu: "4"
      memory: 8Gi
      persistentvolumeclaims: "5"
      requests.storage: "50Gi"
EOF
```

### Step 3: Test Login

```bash
# Port-forward the gateway
kubectl port-forward svc/istio-ingressgateway -n istio-system 8080:80
```

Open browser to `http://localhost:8080` and login with:
- Email: `alice@example.com`
- Password: (the password you used in Step 1)

---

## Using Helper Scripts

### Automated User Creation

Use the helper script for easier setup:

```bash
cd examples/profiles
./create-user-and-profile.sh alice@example.com alice alice-profile
```

This script will:
1. Prompt for password
2. Generate hash
3. Update Dex configuration
4. Create the profile
5. Verify everything is working

### Profile Management

```bash
# List all profiles
./manage-profiles.sh list

# Show profile details
./manage-profiles.sh describe alice-profile

# Check resource usage
./manage-profiles.sh quota alice-profile

# Grant access to another user
./manage-profiles.sh grant alice-profile bob@example.com kubeflow-edit

# List users with access
./manage-profiles.sh users alice-profile
```

---

## Using Example Templates

### Basic Profile (No Quotas)
```bash
cp basic-profile.yaml my-profile.yaml
# Edit my-profile.yaml to set your email
kubectl apply -f my-profile.yaml
```

### Profile with Resource Limits
```bash
cp profile-with-quotas.yaml my-profile.yaml
# Edit my-profile.yaml to customize quotas and email
kubectl apply -f my-profile.yaml
```

### Team Profile (Multiple Users)
```bash
cp team-profile.yaml my-team.yaml
# Edit my-team.yaml to add team members
kubectl apply -f my-team.yaml
```

---

## Common Commands

### Verify Installation
```bash
# Check profile exists
kubectl get profile <profile-name>

# Check namespace created
kubectl get namespace <profile-name>

# Check resource quotas
kubectl describe resourcequota -n <profile-name>

# View all resources in profile
kubectl get all -n <profile-name>
```

### Update Profile
```bash
# Edit profile
kubectl edit profile <profile-name>

# Or patch specific fields
kubectl patch profile <profile-name> --type merge -p '
{
  "spec": {
    "resourceQuotaSpec": {
      "hard": {
        "cpu": "8",
        "memory": "16Gi"
      }
    }
  }
}'
```

### Delete Profile
```bash
# WARNING: This deletes all resources in the namespace
kubectl delete profile <profile-name>
```

---

## Access Control

### Grant User Access
```bash
# Grant edit access
kubectl create rolebinding user-access \
  --clusterrole=kubeflow-edit \
  --user=user@example.com \
  --namespace=<profile-name>

# Grant view-only access
kubectl create rolebinding user-viewer \
  --clusterrole=kubeflow-view \
  --user=viewer@example.com \
  --namespace=<profile-name>

# Grant admin access
kubectl create rolebinding user-admin \
  --clusterrole=kubeflow-admin \
  --user=admin@example.com \
  --namespace=<profile-name>
```

---

## Troubleshooting

### Can't Login
**Problem**: Invalid credentials
**Solution**:
```bash
# Check Dex logs
kubectl logs -n auth deployment/dex | tail -50

# Verify user exists in ConfigMap
kubectl get configmap dex -n auth -o yaml | grep -A5 staticPasswords
```

### Profile Not Working
**Problem**: User can login but sees no profiles
**Solution**: Email mismatch
```bash
# Check what email Dex sees
kubectl logs -n auth deployment/dex | grep -i email

# Check profile owner email
kubectl get profile <name> -o jsonpath='{.spec.owner.name}'

# They must match exactly!
```

### Namespace Not Created
**Problem**: Profile exists but no namespace
**Solution**:
```bash
# Check profile controller
kubectl logs -n kubeflow deployment/profiles-deployment

# Check profile status
kubectl describe profile <name>
```

### Resource Quota Errors
**Problem**: Can't create resources
**Solution**:
```bash
# Check current usage
kubectl describe resourcequota -n <profile-name>

# Increase quota if needed
kubectl patch profile <name> --type merge -p '{"spec":{"resourceQuotaSpec":{"hard":{"cpu":"8"}}}}'
```

---

## Production Best Practices

### 1. Use External Identity Provider
Instead of static passwords, integrate with:
- Azure AD
- Google Workspace
- GitHub
- LDAP
- Keycloak

See: [../../PROFILE_CREATION_GUIDE.md](../../PROFILE_CREATION_GUIDE.md#adding-users-via-external-idps)

### 2. Enable HTTPS
Required for production. Configure your Ingress with TLS certificates.

### 3. Set Resource Quotas
Always set quotas to prevent resource exhaustion:
```yaml
resourceQuotaSpec:
  hard:
    cpu: "4"
    memory: 8Gi
    requests.nvidia.com/gpu: "1"
    persistentvolumeclaims: "5"
    requests.storage: "50Gi"
```

### 4. Regular Audits
```bash
# Review all profiles monthly
./manage-profiles.sh list

# Check resource usage
for profile in $(kubectl get profiles -o name); do
  echo "=== $profile ==="
  ./manage-profiles.sh quota ${profile#profile.kubeflow.org/}
done
```

### 5. Backup Profiles
```bash
# Export all profiles
kubectl get profiles -o yaml > profiles-backup.yaml

# Restore if needed
kubectl apply -f profiles-backup.yaml
```

---

## Next Steps

- **Full Documentation**: [PROFILE_CREATION_GUIDE.md](../../PROFILE_CREATION_GUIDE.md)
- **Example Configurations**: See other YAML files in this directory
- **Main README**: [../../README.md](../../README.md)
- **Dex Integration**: [../../common/dex/README.md](../../common/dex/README.md)

---

## Support

For issues or questions:
1. Check the [Troubleshooting](#troubleshooting) section
2. Review logs: `kubectl logs -n auth deployment/dex`
3. Check profile controller: `kubectl logs -n kubeflow deployment/profiles-deployment`
4. Consult Kubeflow documentation: https://www.kubeflow.org/docs/

---

**Remember**: The email in Dex **MUST** exactly match the email in the Profile's `spec.owner.name`!
