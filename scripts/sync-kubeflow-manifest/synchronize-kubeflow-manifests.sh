#!/usr/bin/env bash
# ==============================================================================
# Script: extract-images.sh
# Purpose: Extract all container images from Kubeflow manifests (components + applications)
# ==============================================================================

set -euo pipefail

REPO_URL="https://github.com/kubeflow/manifests.git"
REPO_BRANCH_OR_TAG="v1.10.0"
SOURCE_DIR=${SOURCE_DIR:-/tmp/kubeflow-manifests}
OUTPUT_FILE=${OUTPUT_FILE:-./images.txt}

log() { echo -e "\033[1;36m[INFO]\033[0m $*"; }

clone_repo() {
  if [ ! -d "${SOURCE_DIR}/.git" ]; then
    log "Cloning Kubeflow manifests repo..."
    rm -rf "${SOURCE_DIR}"
    git clone --depth 1 --branch "${REPO_BRANCH_OR_TAG}" "${REPO_URL}" "${SOURCE_DIR}"
  else
    log "Repo already exists, pulling latest..."
    git -C "${SOURCE_DIR}" fetch --depth 1 origin "${REPO_BRANCH_OR_TAG}" && git -C "${SOURCE_DIR}" checkout "${REPO_BRANCH_OR_TAG}"
  fi
}

extract_images_from_dir() {
  local dir="$1"
  [ ! -d "$dir" ] && return
  grep -RhoE "image:\s*[\"']?([^\"'\s]+)[\"']?" "$dir" |
    sed -E 's/image:\s*["'\'']?//g' |
    tr -d '"' |
    tr -d "'" |
    sort -u
}

main() {
  clone_repo
  log "Extracting images from components and applications..."

  # Tạo file output rỗng
  : > "$OUTPUT_FILE"

  # Quét toàn bộ component manifests
  log "Scanning components..."
  component_images=$(extract_images_from_dir "${SOURCE_DIR}/components")

  # Quét toàn bộ application manifests
  log "Scanning applications..."
  app_images=$(extract_images_from_dir "${SOURCE_DIR}/applications")

  # Gộp kết quả, remove duplicates
  {
    echo "$component_images"
    echo "$app_images"
  } | sort -u > "$OUTPUT_FILE"

  log "✅ Found $(wc -l < "$OUTPUT_FILE") unique images."
  log "📦 Output written to: $OUTPUT_FILE"
}

main "$@"
