#!/bin/bash
set -euo pipefail

# Script to update repository URLs in ArgoCD applications
# Usage: ./update-repo-urls.sh <your-git-repo-url> [target-revision]

#=============================================================================
# Functions
#=============================================================================

show_usage() {
  echo "Usage: $0 <repository-url> [target-revision]"
  echo ""
  echo "Arguments:"
  echo "  repository-url    - Git repository URL"
  echo "  target-revision   - Git branch/tag/commit (default: main)"
  echo ""
  echo "Examples:"
  echo "  $0 https://github.com/myorg/kubeflow-manifests"
  echo "  $0 https://github.com/myorg/kubeflow-manifests develop"
  echo "  $0 https://github.com/myorg/kubeflow-manifests v1.0.0"
}

update_yaml() {
  local file="$1"
  local repo_url="$2"
  local target_revision="$3"

  if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS (BSD sed)
    sed -i '' "s|repoURL:.*|repoURL: $repo_url|g" "$file"
    sed -i '' "s|targetRevision:.*|targetRevision: $target_revision|g" "$file"
  else
    # Linux (GNU sed)
    sed -i "s|repoURL:.*|repoURL: $repo_url|g" "$file"
    sed -i "s|targetRevision:.*|targetRevision: $target_revision|g" "$file"
  fi
}

update_configmap() {
  local file="$1"
  local repo_url="$2"
  local target_revision="$3"

  if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS (BSD sed)
    sed -i '' "s|REPO_URL:.*|REPO_URL: $repo_url|g" "$file"
    sed -i '' "s|TARGET_REVISION:.*|TARGET_REVISION: $target_revision|g" "$file"
  else
    # Linux (GNU sed)
    sed -i "s|REPO_URL:.*|REPO_URL: $repo_url|g" "$file"
    sed -i "s|TARGET_REVISION:.*|TARGET_REVISION: $target_revision|g" "$file"
  fi
}

#=============================================================================
# Main Script
#=============================================================================

# Check arguments
if [ $# -eq 0 ]; then
  show_usage
  exit 1
fi

REPO_URL="$1"
TARGET_REVISION="${2:-main}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo ""
echo "Updating Repository URLs"
echo "============================================================"
echo "  Repository:  $REPO_URL"
echo "  Revision:    $TARGET_REVISION"
echo "  Directory:   $SCRIPT_DIR"
echo "============================================================"
echo ""

# Counter for updated files
UPDATED_COUNT=0

# Update application files in apps directory
if [ -d "$SCRIPT_DIR/apps" ]; then
  echo "Updating application manifests in apps/..."
  while IFS= read -r -d '' file; do
    echo "  [OK] $(basename "$file")"
    update_yaml "$file" "$REPO_URL" "$TARGET_REVISION"
    UPDATED_COUNT=$((UPDATED_COUNT + 1))
  done < <(find "$SCRIPT_DIR/apps" -name "*.yaml" -type f -print0)
fi

# Update root application files
echo ""
echo "Updating root applications..."
for file in argocd-application.yaml argocd-bootstrap.yaml app-of-apps.yaml; do
  if [ -f "$SCRIPT_DIR/$file" ]; then
    echo "  [OK] $file"
    update_yaml "$SCRIPT_DIR/$file" "$REPO_URL" "$TARGET_REVISION"
    UPDATED_COUNT=$((UPDATED_COUNT + 1))
  else
    echo "  [SKIP] $file (not found - skipping)"
  fi
done

# Update value-config.yaml if exists
echo ""
echo "Updating configuration files..."
if [ -f "$SCRIPT_DIR/value-config.yaml" ]; then
  echo "  [OK] value-config.yaml"
  update_configmap "$SCRIPT_DIR/value-config.yaml" "$REPO_URL" "$TARGET_REVISION"
  UPDATED_COUNT=$((UPDATED_COUNT + 1))
else
  echo "  [SKIP] value-config.yaml (not found - skipping)"
fi

# Validate changes (optional - requires yq)
echo ""
if command -v yq > /dev/null 2>&1; then
  echo "Validating changes..."
  VALIDATION_FAILED=0

  # Check a sample file
  if [ -f "$SCRIPT_DIR/argocd-bootstrap.yaml" ]; then
    ACTUAL_URL=$(yq e '.spec.source.repoURL' "$SCRIPT_DIR/argocd-bootstrap.yaml")
    ACTUAL_REV=$(yq e '.spec.source.targetRevision' "$SCRIPT_DIR/argocd-bootstrap.yaml")

    if [ "$ACTUAL_URL" = "$REPO_URL" ] && [ "$ACTUAL_REV" = "$TARGET_REVISION" ]; then
      echo "  [OK] Validation passed"
    else
      echo "  [ERROR] Validation failed"
      echo "          Expected: $REPO_URL @ $TARGET_REVISION"
      echo "          Got:      $ACTUAL_URL @ $ACTUAL_REV"
      VALIDATION_FAILED=1
    fi
  fi

  if [ $VALIDATION_FAILED -eq 1 ]; then
    echo ""
    echo "WARNING: Validation failed - please check the changes"
  fi
else
  echo "TIP: Install yq for validation (brew install yq)"
fi

# Summary
echo ""
echo "============================================================"
echo "Repository URLs Updated Successfully!"
echo "============================================================"
echo ""
echo "Summary:"
echo "  Files Updated:  $UPDATED_COUNT"
echo "  Repository:     $REPO_URL"
echo "  Target Rev:     $TARGET_REVISION"
echo ""
echo "Next Steps:"
echo "  1. Review changes:  git diff"
echo "  2. Test locally:    make validate"
echo "  3. Commit changes:  git add . && git commit -m 'Update repo URLs'"
echo "  4. Push to Git:     git push"
echo "  5. Deploy:          make deploy-app-of-apps"
echo "  6. Monitor:         make watch-apps"
echo ""
