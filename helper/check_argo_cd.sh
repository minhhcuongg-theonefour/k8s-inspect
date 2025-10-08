#!/usr/bin/env bash

set -euo pipefail

NAMESPACE="argocd"
RELEASE_NAME="argocd"
HELM_REPO_NAME="argo"
HELM_REPO_URL="https://argoproj.github.io/argo-helm"
CHART_NAME="argo-cd"

echo "🔍 Checking if Argo CD is already installed in namespace '$NAMESPACE'..."

# Check if namespace exists
if kubectl get ns "$NAMESPACE" >/dev/null 2>&1; then
  echo "Namespace '$NAMESPACE' already exists."
else
  echo "Creating namespace '$NAMESPACE'..."
  kubectl create namespace "$NAMESPACE"
fi

# Check if Helm release exists
if helm status "$RELEASE_NAME" -n "$NAMESPACE" >/dev/null 2>&1; then
  echo "Argo CD Helm release '$RELEASE_NAME' already installed in '$NAMESPACE'."
else
  echo "Installing Argo CD via Helm..."

  # Add repo if not added
  if ! helm repo list | grep -q "$HELM_REPO_NAME"; then
    helm repo add "$HELM_REPO_NAME" "$HELM_REPO_URL"
  fi

  helm repo update

  # Install Argo CD with Helm
  helm upgrade --install "$RELEASE_NAME" \
    "$HELM_REPO_NAME"/"$CHART_NAME" \
    -n "$NAMESPACE" \
    --create-namespace



  echo "✅ Argo CD installed successfully!"
fi

# Optional: Display Argo CD access info
echo
echo "🔑 To access Argo CD UI:"
echo "  kubectl get svc -n $NAMESPACE argocd-server"
echo "  kubectl get secret argocd-initial-admin-secret -ojsonpath={.data.password} -n argocd | base64 --decode"