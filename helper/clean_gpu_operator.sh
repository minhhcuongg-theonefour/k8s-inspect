#!/bin/bash

set -e

echo "🚀 Cleaning up NVIDIA GPU Operator (Helm + CRDs + RBAC + namespace)..."

# 1️⃣ Xác định namespace GPU Operator (mặc định: gpu-operator)
NS=${1:-gpu-operator}

echo "🔍 Step 1: Uninstall all Helm releases in namespace $NS..."
for release in $(helm list -n "$NS" -q); do
  echo "   ➤ Uninstalling Helm release: $release"
  helm uninstall "$release" -n "$NS" || true
done

# 2️⃣ Xóa ClusterRole / ClusterRoleBinding
echo "🧩 Step 2: Deleting ClusterRole and ClusterRoleBinding..."
kubectl delete clusterrole gpu-operator --ignore-not-found
kubectl delete clusterrolebinding gpu-operator --ignore-not-found

# 3️⃣ Xóa CRDs (ClusterPolicy, DriverComponent, v.v.)
echo "📦 Step 3: Deleting NVIDIA CRDs..."
kubectl delete crd clusterpolicies.nvidia.com --ignore-not-found
kubectl delete crd drivercomponents.nvidia.com --ignore-not-found
kubectl delete crd nodefeaturediscoveries.nfd.k8s-sigs.io --ignore-not-found

# 4️⃣ Delete namespace
echo "🧽 Step 4: Deleting namespace $NS..."
kubectl delete namespace "$NS" --ignore-not-found --wait=false

# 5️⃣ Xóa DaemonSet nvidia-device-plugin (nếu còn)
echo "🔧 Step 5: Deleting NVIDIA device plugin DaemonSet..."
kubectl delete daemonset nvidia-device-plugin-daemonset -n kube-system --ignore-not-found

# 6️⃣ Xóa label GPU khỏi node (nếu còn)
echo "🧠 Step 6: Cleaning GPU labels from nodes..."
for node in $(kubectl get nodes -o name); do
  kubectl label $node nvidia.com/gpu.present- --ignore-not-found || true
done

echo "✅ GPU Operator cleanup complete!"
