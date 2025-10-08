#!/bin/bash
set -euo pipefail

# Script to update repository URLs in ArgoCD applications
# Usage: ./update-repo-urls.sh <your-git-repo-url>

if [ $# -eq 0 ]; then
    echo "Usage: $0 <repository-url>"
    echo "Example: $0 https://github.com/myorg/kubeflow-manifests"
    exit 1
fi

REPO_URL="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Updating repository URLs to: $REPO_URL"

# Update app-of-apps.yaml
sed -i.bak "s|https://github.com/your-org/kubeflow-manifests|$REPO_URL|g" "$SCRIPT_DIR/app-of-apps.yaml"

# Update all application files in apps directory
find "$SCRIPT_DIR/apps" -name "*.yaml" -exec sed -i.bak "s|https://github.com/your-org/kubeflow-manifests|$REPO_URL|g" {} \;

# Remove backup files
find "$SCRIPT_DIR" -name "*.bak" -delete

echo "✅ Repository URLs updated successfully!"
echo "📝 Next steps:"
echo "   1. Commit and push changes to your Git repository"
echo "   2. Apply the App of Apps: kubectl apply -f argocd/app-of-apps.yaml"
echo "   3. Monitor deployment: argocd app list"
