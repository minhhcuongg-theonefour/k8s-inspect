#!/bin/bash
set -e

NAMESPACE="argocd"
RELEASE_NAME="argocd"

echo "🚀 Checking if ArgoCD Helm release exists in namespace '$NAMESPACE'..."

# Check if namespace exists
if kubectl get namespace "$NAMESPACE" > /dev/null 2>&1; then
  echo "✅ Namespace $NAMESPACE found."
else
  echo "⚠️ Namespace $NAMESPACE does not exist. Nothing to uninstall."
  exit 0
fi

# Check if Helm exists
if helm list -n "$NAMESPACE" | grep -q "$RELEASE_NAME"; then
  echo "🧹 Uninstalling ArgoCD Helm release..."
  helm uninstall "$RELEASE_NAME" -n "$NAMESPACE" || true
else
  echo "ℹ️ Helm release $RELEASE_NAME not found. Skipping helm uninstall."
fi

echo "⏳ Waiting a few seconds for resources to be deleted..."
sleep 5

# Remove CRD (Custom Resource Definitions) created by ArgoCD
echo "🧩 Removing ArgoCD CRDs..."
kubectl get crd | grep argoproj.io | awk '{print $1}' | xargs -r kubectl delete crd

# Delete namespace
echo "🔥 Deleting namespace $NAMESPACE..."
kubectl delete namespace "$NAMESPACE" --wait || true

echo "🧽 Cleaning up any leftover cluster roles or bindings..."
kubectl delete clusterrole,clusterrolebinding -l app.kubernetes.io/part-of=argocd --ignore-not-found

echo "✅ ArgoCD has been completely removed from your cluster."
