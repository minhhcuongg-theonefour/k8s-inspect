# Kubeflow ArgoCD App of Apps Pattern

This directory contains ArgoCD Application manifests implementing the "App of Apps" pattern for managing Kubeflow components.

## Architecture

```
kubeflow-app-of-apps (Root Application)
├── common-services (Istio, Cert-Manager, Dex, etc.)
├── kubeflow-pipelines (ML Pipelines)
├── katib (Hyperparameter Tuning)
├── kserve (Model Serving)
├── jupyter (Notebook Environment)
├── training (Training Operator v2)
├── model-registry (Model Management)
├── web-apps (Dashboard, Volume UI, etc.)
└── spark (Spark Operator)
```

## Prerequisites

1. **ArgoCD installed** in your cluster
2. **Git repository** with these manifests
3. **Kubernetes cluster** with sufficient resources

## Setup Instructions

### 1. Update Repository URLs

Replace `https://github.com/your-org/kubeflow-manifests` in all YAML files with your actual repository URL:

```bash
find argocd/apps -name "*.yaml" -exec sed -i 's|your-org/kubeflow-manifests|YOUR_ORG/YOUR_REPO|g' {} \;
```

### 2. Deploy the App of Apps

```bash
# Apply the root application
kubectl apply -f bootstrap/argocd/app-of-apps.yaml

# Or apply individual applications
kubectl apply -f bootstrap/argocd/apps/
```

### 3. Monitor Deployment

```bash
# Check ArgoCD applications
kubectl get applications -n argocd

# Check application status
argocd app list
argocd app get kubeflow-bootstrap
```

## Component Details

### Common Services (`common-services.yaml`)
- **Istio**: Service mesh and ingress
- **Cert-Manager**: Certificate management
- **Dex**: Authentication provider
- **OAuth2-Proxy**: Authentication proxy
- **Knative**: Serverless platform

### Kubeflow Applications

| Application | Path | Namespace | Description |
|-------------|------|-----------|-------------|
| `kubeflow-pipelines` | `applications/pipeline/upstream/env/cert-manager/platform-agnostic-multi-user` | `kubeflow` | ML Pipelines with multi-user support |
| `katib` | `applications/katib/upstream/installs/katib-with-kubeflow` | `kubeflow` | Hyperparameter optimization |
| `kserve` | `applications/kserve/kserve` | `kubeflow` | Model serving platform |
| `jupyter` | `applications/jupyter/*/overlays/*` | `kubeflow` | Notebook environment |
| `training` | `applications/trainer/overlays` | `kubeflow-system` | Distributed training |
| `model-registry` | `applications/model-registry/upstream/overlays/db` | `kubeflow` | Model lifecycle management |
| `web-apps` | `applications/*/overlays/istio` | `kubeflow` | Web UIs and dashboards |
| `spark` | `applications/spark/spark-operator/overlays/kubeflow` | `kubeflow` | Spark job execution |

## Sync Policies

All applications are configured with:
- **Automated sync**: `prune: true`, `selfHeal: true`
- **Server-side apply**: For better conflict resolution
- **Retry logic**: 5 attempts with exponential backoff
- **Ignore differences**: For webhook certificates and dynamic content

## Customization

### Sync Waves
Applications are deployed in order using sync waves:
- Wave 0: Common services (Istio, Cert-Manager)
- Wave 1: Kubeflow applications

### Resource Exclusions
Some resources are ignored to prevent sync conflicts:
- Webhook certificates (auto-generated)
- ConfigMaps with dynamic content
- Workflow templates

### Environment-Specific Overlays

Create environment-specific overlays:

```yaml
# argocd/overlays/staging/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
- ../../apps

patchesStrategicMerge:
- staging-patches.yaml
```

## Troubleshooting

### Common Issues

1. **Webhook Certificate Errors**
   ```bash
   # Delete and recreate certificates
   kubectl delete certificate --all -n kubeflow
   argocd app sync kubeflow-kserve --force
   ```

2. **Resource Conflicts**
   ```bash
   # Force sync with replace
   argocd app sync kubeflow-pipelines --replace
   ```

3. **Dependency Issues**
   ```bash
   # Sync in order
   argocd app sync common-services
   argocd app sync kubeflow-pipelines
   ```

### Monitoring

```bash
# Watch application health
argocd app list --watch

# Get detailed status
argocd app get kubeflow-pipelines --show-params

# View sync history
argocd app history kubeflow-pipelines
```

## Security Considerations

1. **Repository Access**: Ensure ArgoCD has read access to your Git repository
2. **RBAC**: Configure appropriate permissions for ArgoCD service account
3. **Secrets**: Use sealed-secrets or external-secrets for sensitive data
4. **Network Policies**: Apply network policies to restrict traffic

## Migration from Manual Deployment

1. **Export existing resources**:
   ```bash
   kubectl get all -n kubeflow -o yaml > existing-resources.yaml
   ```

2. **Apply ArgoCD applications**:
   ```bash
   kubectl apply -f argocd/app-of-apps.yaml
   ```

3. **Let ArgoCD adopt resources**:
   ```bash
   argocd app sync kubeflow-pipelines --force
   ```

## Benefits of App of Apps Pattern

- ✅ **Modular Management**: Each component can be managed independently
- ✅ **Dependency Control**: Control deployment order and dependencies
- ✅ **Environment Consistency**: Ensure consistent deployments across environments
- ✅ **GitOps Workflow**: Full GitOps with version control and rollback
- ✅ **Scalability**: Easy to add/remove components
- ✅ **Observability**: Clear visibility into each component's health
