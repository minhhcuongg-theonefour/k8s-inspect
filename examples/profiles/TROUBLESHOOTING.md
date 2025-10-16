# Troubleshooting Guide: Kubeflow Profiles

This guide helps you diagnose and fix common issues when creating Kubeflow profiles with authentication.

## Quick Diagnostics

Run the pre-flight check script first:
```bash
./check-prerequisites.sh
```

This will identify most common issues automatically.

---

## Common Errors and Solutions

### 1. Profile CRD Not Found

**Error:**
```
error: resource mapping not found for name: "profile-name" namespace: "" from "file.yaml":
no matches for kind "Profile" in version "kubeflow.org/v1"
ensure CRDs are installed first
```

**Cause:** The Profile Custom Resource Definition (CRD) is not installed.

**Solution:**

Check if Profile CRD exists:
```bash
kubectl get crd profiles.kubeflow.org
```

If not found, install the profiles component:
```bash
# Install profiles and dependencies
kustomize build applications/profiles/upstream/overlays/kubeflow | kubectl apply -f -

# Wait for it to be ready
kubectl wait --for=condition=Ready pods -l app=profiles -n kubeflow --timeout=180s
```

Or install full Kubeflow:
```bash
while ! kustomize build example | kubectl apply --server-side --force-conflicts -f -; do
  echo "Retrying...";
  sleep 20;
done
```

---

### 2. User Can Login But Sees "No Profiles Available"

**Error:** User successfully authenticates but dashboard shows no available profiles.

**Cause:** Email mismatch between Dex and Profile.

**Solution:**

1. Check what email Dex sees:
```bash
kubectl logs -n auth deployment/dex | grep -i "login" | tail -20
```

2. Check profile owner email:
```bash
kubectl get profile <profile-name> -o jsonpath='{.spec.owner.name}'
echo ""
```

3. Ensure they match **exactly** (case-sensitive):
```bash
# Example: Both should be "alice@example.com"
# NOT: "Alice@example.com" or "alice@EXAMPLE.com"
```

4. Fix the profile if needed:
```bash
kubectl edit profile <profile-name>
# Update spec.owner.name to match Dex email
```

---

### 3. Authentication Loops or Redirects

**Error:** Browser keeps redirecting between login page and dashboard.

**Cause:** OAuth2-Proxy or Dex misconfiguration.

**Solutions:**

Check OAuth2-Proxy logs:
```bash
kubectl logs -n oauth2-proxy deployment/oauth2-proxy | tail -50
```

Check Dex logs:
```bash
kubectl logs -n auth deployment/dex | tail -50
```

Common issues:
- **Cookie domain mismatch**: Check OAuth2-Proxy cookie settings
- **OIDC client secret mismatch**: Verify secrets match in Dex and OAuth2-Proxy
- **Issuer URL mismatch**: Ensure Dex issuer URL is consistent

Verify Dex OIDC client configuration:
```bash
kubectl get secret dex-oidc-client -n auth -o jsonpath='{.data.OIDC_CLIENT_ID}' | base64 -d
echo ""
kubectl get secret dex-oidc-client -n auth -o jsonpath='{.data.OIDC_CLIENT_SECRET}' | base64 -d
echo ""
```

---

### 4. Profile Controller Not Running

**Error:** Profiles created but namespaces not appearing.

**Cause:** Profile controller deployment is not running.

**Solution:**

Check controller status:
```bash
kubectl get pods -n kubeflow | grep profile
```

If not running or crashing:
```bash
# Check logs
kubectl logs -n kubeflow deployment/profiles-deployment

# Check deployment status
kubectl describe deployment profiles-deployment -n kubeflow

# Common fixes:
# 1. Restart the deployment
kubectl rollout restart deployment profiles-deployment -n kubeflow

# 2. Check for image pull errors
kubectl get pods -n kubeflow -l app=profiles -o yaml | grep -A5 "image:"

# 3. Verify RBAC permissions
kubectl get clusterrole profile-controller-role
kubectl get clusterrolebinding profile-controller-role-binding
```

---

### 5. "Invalid Password" or Cannot Login

**Error:** User cannot authenticate with provided credentials.

**Cause:** Password hash mismatch or not configured correctly.

**Solution:**

1. Regenerate password hash:
```bash
python3 -c 'from passlib.hash import bcrypt; import getpass; print(bcrypt.using(rounds=12, ident="2y").hash(getpass.getpass()))'
```

2. Update the secret:
```bash
# Replace USERNAME with actual username (uppercase)
kubectl patch secret dex-passwords -n auth --type merge \
  -p '{"stringData":{"DEX_USERNAME_PASSWORD":"<NEW_HASH>"}}'
```

3. Restart Dex:
```bash
kubectl rollout restart deployment dex -n auth
kubectl wait --for=condition=Ready pods -l app=dex -n auth --timeout=180s
```

4. Verify password hash is loaded:
```bash
# Check if environment variable is set in Dex pod
kubectl exec -n auth deployment/dex -- env | grep DEX_
```

---

### 6. Resource Quota Exceeded

**Error:** Cannot create notebooks, pipelines, or other resources.

**Cause:** Profile resource quota limits reached.

**Solution:**

Check current usage:
```bash
kubectl describe resourcequota -n <profile-namespace>
```

Output shows:
```
Name:                   <quota-name>
Namespace:              <profile-namespace>
Resource                Used  Hard
--------                ----  ----
cpu                     4     4    <-- At limit!
memory                  8Gi   8Gi  <-- At limit!
```

Increase quota:
```bash
kubectl patch profile <profile-name> --type merge -p '
{
  "spec": {
    "resourceQuotaSpec": {
      "hard": {
        "cpu": "8",
        "memory": "16Gi",
        "requests.nvidia.com/gpu": "2"
      }
    }
  }
}'
```

Or temporarily remove quota (not recommended for production):
```bash
kubectl edit profile <profile-name>
# Remove or comment out resourceQuotaSpec section
```

---

### 7. Dex Not Found or Not Ready

**Error:** Cannot access Dex or authentication fails immediately.

**Cause:** Dex is not deployed or not ready.

**Solution:**

Check Dex status:
```bash
kubectl get pods -n auth
kubectl get deployment dex -n auth
```

Install Dex if missing:
```bash
kustomize build common/dex/overlays/oauth2-proxy | kubectl apply -f -
kubectl wait --for=condition=Ready pods -l app=dex -n auth --timeout=180s
```

Check Dex service:
```bash
kubectl get service dex -n auth
```

Test Dex connectivity from within cluster:
```bash
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- \
  curl http://dex.auth.svc.cluster.local:5556/dex/.well-known/openid-configuration
```

---

### 8. Istio Authorization Denied

**Error:** `RBAC: access denied` when accessing Kubeflow UI.

**Cause:** Istio authorization policies blocking access.

**Solution:**

Check Istio authorization policies:
```bash
kubectl get authorizationpolicy -n istio-system
kubectl get authorizationpolicy -n kubeflow
```

Check RequestAuthentication:
```bash
kubectl get requestauthentication -n istio-system -o yaml
```

Verify JWT claims are being extracted:
```bash
# Should include kubeflow-userid header mapping
kubectl get requestauthentication dex-jwt -n istio-system -o yaml
```

Check Istio ingress gateway logs:
```bash
kubectl logs -n istio-system deployment/istio-ingressgateway | tail -50
```

---

### 9. Namespace Not Created After Profile Apply

**Error:** Profile exists but namespace doesn't appear.

**Cause:** Profile controller can't create namespace or RBAC issues.

**Solution:**

Check profile status:
```bash
kubectl describe profile <profile-name>
```

Look for events or conditions showing errors.

Check profile controller logs:
```bash
kubectl logs -n kubeflow deployment/profiles-deployment | grep -i error
```

Common causes:
- **RBAC insufficient**: Profile controller needs cluster-admin or appropriate permissions
- **Name conflict**: Namespace already exists with different owner
- **Finalizers stuck**: Profile has finalizers preventing updates

Manually check if namespace exists:
```bash
kubectl get namespace <profile-name>
```

If namespace exists but not associated:
```bash
# Check namespace labels
kubectl get namespace <profile-name> -o yaml

# Should have labels like:
#   app.kubernetes.io/part-of: kubeflow-profile
#   katib.kubeflow.org/metrics-collector-injection: enabled
```

---

### 10. Cannot Delete Profile

**Error:** Profile stuck in `Terminating` state.

**Cause:** Finalizers preventing deletion or resources still exist.

**Solution:**

Check profile finalizers:
```bash
kubectl get profile <profile-name> -o yaml | grep -A5 finalizers
```

Force remove finalizers (use with caution):
```bash
kubectl patch profile <profile-name> -p '{"metadata":{"finalizers":[]}}' --type=merge
```

Check for stuck resources in namespace:
```bash
kubectl api-resources --verbs=list --namespaced -o name | \
  xargs -n 1 kubectl get --show-kind --ignore-not-found -n <profile-name>
```

Force delete namespace if needed:
```bash
kubectl delete namespace <profile-name> --force --grace-period=0
```

---

## Diagnostic Commands

### Full System Check
```bash
# Run all checks
./check-prerequisites.sh

# Or manually check each component:

# 1. Cluster connectivity
kubectl cluster-info

# 2. Kubeflow pods
kubectl get pods -n kubeflow
kubectl get pods -n auth
kubectl get pods -n oauth2-proxy
kubectl get pods -n istio-system

# 3. CRDs
kubectl get crd | grep kubeflow

# 4. Profiles
kubectl get profiles
kubectl get profiles -o yaml

# 5. Services
kubectl get svc -n istio-system istio-ingressgateway
kubectl get svc -n auth dex
kubectl get svc -n oauth2-proxy oauth2-proxy
```

### Check Authentication Flow
```bash
# 1. Port-forward gateway
kubectl port-forward svc/istio-ingressgateway -n istio-system 8080:80 &
PF_PID=$!

# 2. Test Dex discovery endpoint
curl -k http://localhost:8080/dex/.well-known/openid-configuration

# 3. Check OAuth2 Proxy
curl -k http://localhost:8080/oauth2/auth

# 4. Stop port-forward
kill $PF_PID
```

### Export Current Configuration
```bash
# Export for troubleshooting or backup
kubectl get profiles -o yaml > profiles-export.yaml
kubectl get configmap dex -n auth -o yaml > dex-config.yaml
kubectl get configmap profiles-config -n kubeflow -o yaml > profiles-config.yaml
```

---

## Getting Help

### Check Logs
Always check logs when troubleshooting:

```bash
# Dex
kubectl logs -n auth deployment/dex --tail=100

# OAuth2-Proxy
kubectl logs -n oauth2-proxy deployment/oauth2-proxy --tail=100

# Profile Controller
kubectl logs -n kubeflow deployment/profiles-deployment --tail=100

# Istio Ingress Gateway
kubectl logs -n istio-system deployment/istio-ingressgateway --tail=100
```

### Verify Events
```bash
# Profile events
kubectl describe profile <profile-name>

# Namespace events
kubectl get events -n <profile-namespace> --sort-by='.lastTimestamp'

# Cluster events
kubectl get events --all-namespaces --sort-by='.lastTimestamp' | tail -50
```

### Debug Mode
Enable debug logging for more details:

```bash
# Dex debug mode (edit ConfigMap)
kubectl edit configmap dex -n auth
# Change: level: "debug"

# Profile controller debug
kubectl set env deployment/profiles-deployment -n kubeflow LOG_LEVEL=debug

# OAuth2-Proxy debug
kubectl set env deployment/oauth2-proxy -n oauth2-proxy OAUTH2_PROXY_LOGGING_LEVEL=debug
```

---

## Common Patterns

### Pattern 1: Fresh Installation
After installing Kubeflow, you need to:
1. Wait for all pods to be Ready
2. Configure Dex with users
3. Create profiles matching those users
4. Test login

### Pattern 2: Adding New User
1. Add user to Dex ConfigMap
2. Add password hash to dex-passwords secret
3. Restart Dex
4. Create Profile with matching email
5. Verify namespace created
6. Test login

### Pattern 3: Updating Existing User
1. Update Dex ConfigMap (if changing email)
2. Update password hash (if changing password)
3. Restart Dex
4. Update Profile owner if email changed
5. Test login

---

## Prevention Tips

### Before Creating Profiles
1. Run `./check-prerequisites.sh`
2. Ensure all Kubeflow components are Ready
3. Verify Dex configuration is correct
4. Test with one profile first

### Best Practices
1. **Use External IDP in Production**: Avoid static passwords
2. **Enable HTTPS**: Required for secure cookies
3. **Set Resource Quotas**: Prevent resource exhaustion
4. **Regular Backups**: Export profiles regularly
5. **Monitor Logs**: Set up log aggregation
6. **Test in Dev First**: Never test directly in production

---

## Still Having Issues?

1. Run the pre-flight check: `./check-prerequisites.sh`
2. Review this troubleshooting guide
3. Check component logs
4. Review Kubeflow documentation: https://www.kubeflow.org/docs/
5. Ask on Kubeflow Slack: #kubeflow-platform
6. Search GitHub issues: https://github.com/kubeflow/manifests/issues

---

**Remember:** Most profile issues are due to email mismatches or missing CRDs!
