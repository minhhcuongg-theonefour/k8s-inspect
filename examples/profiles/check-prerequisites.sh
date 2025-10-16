#!/bin/bash
#
# Pre-flight check script for Kubeflow Profile creation
# This script checks if all prerequisites are met before creating profiles
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored messages
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

ERRORS=0
WARNINGS=0

echo "============================================"
echo "  Kubeflow Profile Prerequisites Check"
echo "============================================"
echo ""

# Check 1: kubectl
print_info "Checking kubectl..."
if command -v kubectl &> /dev/null; then
    KUBECTL_VERSION=$(kubectl version --client --short 2>/dev/null || kubectl version --client 2>/dev/null | head -1)
    print_success "kubectl is installed: $KUBECTL_VERSION"
else
    print_error "kubectl is not installed"
    echo "  Install: https://kubernetes.io/docs/tasks/tools/"
    ERRORS=$((ERRORS + 1))
fi
echo ""

# Check 2: Cluster connectivity
print_info "Checking cluster connectivity..."
if kubectl cluster-info &> /dev/null; then
    print_success "Connected to Kubernetes cluster"
    CLUSTER_VERSION=$(kubectl version --short 2>/dev/null | grep Server || kubectl version | grep Server)
    echo "  $CLUSTER_VERSION"
else
    print_error "Cannot connect to Kubernetes cluster"
    echo "  Check your kubeconfig: echo \$KUBECONFIG"
    ERRORS=$((ERRORS + 1))
fi
echo ""

# Check 3: Profile CRD
print_info "Checking Profile CRD..."
if kubectl get crd profiles.kubeflow.org &> /dev/null; then
    print_success "Profile CRD is installed"

    # Check API versions
    API_VERSIONS=$(kubectl get crd profiles.kubeflow.org -o jsonpath='{.spec.versions[*].name}')
    echo "  Available versions: $API_VERSIONS"

    # Check if v1 is served
    V1_SERVED=$(kubectl get crd profiles.kubeflow.org -o jsonpath='{.spec.versions[?(@.name=="v1")].served}')
    if [ "$V1_SERVED" = "true" ]; then
        print_success "API version v1 is served"
    else
        print_warning "API version v1 is not served"
        WARNINGS=$((WARNINGS + 1))
    fi
else
    print_error "Profile CRD is not installed"
    echo "  Install with: kustomize build applications/profiles/upstream/overlays/kubeflow | kubectl apply -f -"
    ERRORS=$((ERRORS + 1))
fi
echo ""

# Check 4: Profile Controller
print_info "Checking Profile Controller..."
if kubectl get deployment profiles-deployment -n kubeflow &> /dev/null; then
    READY=$(kubectl get deployment profiles-deployment -n kubeflow -o jsonpath='{.status.readyReplicas}')
    DESIRED=$(kubectl get deployment profiles-deployment -n kubeflow -o jsonpath='{.status.replicas}')

    if [ "$READY" = "$DESIRED" ] && [ "$READY" != "" ]; then
        print_success "Profile Controller is running ($READY/$DESIRED ready)"
    else
        print_warning "Profile Controller is not ready ($READY/$DESIRED ready)"
        echo "  Check logs: kubectl logs -n kubeflow deployment/profiles-deployment"
        WARNINGS=$((WARNINGS + 1))
    fi
else
    print_error "Profile Controller is not deployed"
    echo "  Install with: kustomize build applications/profiles/upstream/overlays/kubeflow | kubectl apply -f -"
    ERRORS=$((ERRORS + 1))
fi
echo ""

# Check 5: Dex
print_info "Checking Dex..."
if kubectl get deployment dex -n auth &> /dev/null; then
    READY=$(kubectl get deployment dex -n auth -o jsonpath='{.status.readyReplicas}')
    DESIRED=$(kubectl get deployment dex -n auth -o jsonpath='{.status.replicas}')

    if [ "$READY" = "$DESIRED" ] && [ "$READY" != "" ]; then
        print_success "Dex is running ($READY/$DESIRED ready)"
    else
        print_warning "Dex is not ready ($READY/$DESIRED ready)"
        echo "  Check logs: kubectl logs -n auth deployment/dex"
        WARNINGS=$((WARNINGS + 1))
    fi

    # Check Dex ConfigMap
    if kubectl get configmap dex -n auth &> /dev/null; then
        print_success "Dex ConfigMap exists"
    else
        print_error "Dex ConfigMap not found"
        ERRORS=$((ERRORS + 1))
    fi

    # Check Dex Secret
    if kubectl get secret dex-passwords -n auth &> /dev/null; then
        print_success "Dex passwords secret exists"
    else
        print_warning "Dex passwords secret not found"
        echo "  You may need to create it when adding users"
        WARNINGS=$((WARNINGS + 1))
    fi
else
    print_error "Dex is not deployed"
    echo "  Install with: kustomize build common/dex/overlays/oauth2-proxy | kubectl apply -f -"
    ERRORS=$((ERRORS + 1))
fi
echo ""

# Check 6: OAuth2-Proxy
print_info "Checking OAuth2-Proxy..."
if kubectl get deployment oauth2-proxy -n oauth2-proxy &> /dev/null; then
    READY=$(kubectl get deployment oauth2-proxy -n oauth2-proxy -o jsonpath='{.status.readyReplicas}')
    DESIRED=$(kubectl get deployment oauth2-proxy -n oauth2-proxy -o jsonpath='{.status.replicas}')

    if [ "$READY" = "$DESIRED" ] && [ "$READY" != "" ]; then
        print_success "OAuth2-Proxy is running ($READY/$DESIRED ready)"
    else
        print_warning "OAuth2-Proxy is not ready ($READY/$DESIRED ready)"
        WARNINGS=$((WARNINGS + 1))
    fi
else
    print_error "OAuth2-Proxy is not deployed"
    echo "  Install with: kustomize build common/oauth2-proxy/overlays/m2m-dex-only | kubectl apply -f -"
    ERRORS=$((ERRORS + 1))
fi
echo ""

# Check 7: Istio
print_info "Checking Istio..."
if kubectl get namespace istio-system &> /dev/null; then
    if kubectl get deployment istiod -n istio-system &> /dev/null; then
        READY=$(kubectl get deployment istiod -n istio-system -o jsonpath='{.status.readyReplicas}')
        DESIRED=$(kubectl get deployment istiod -n istio-system -o jsonpath='{.status.replicas}')

        if [ "$READY" = "$DESIRED" ] && [ "$READY" != "" ]; then
            print_success "Istio is running ($READY/$DESIRED ready)"
        else
            print_warning "Istio is not ready ($READY/$DESIRED ready)"
            WARNINGS=$((WARNINGS + 1))
        fi
    else
        print_error "Istio control plane not found"
        ERRORS=$((ERRORS + 1))
    fi

    # Check Ingress Gateway
    if kubectl get service istio-ingressgateway -n istio-system &> /dev/null; then
        print_success "Istio Ingress Gateway service exists"
    else
        print_warning "Istio Ingress Gateway service not found"
        WARNINGS=$((WARNINGS + 1))
    fi
else
    print_error "Istio is not deployed"
    echo "  Install with: kustomize build common/istio/istio-install/overlays/oauth2-proxy | kubectl apply -f -"
    ERRORS=$((ERRORS + 1))
fi
echo ""

# Check 8: Python and dependencies
print_info "Checking Python environment..."
if command -v python3 &> /dev/null; then
    PYTHON_VERSION=$(python3 --version)
    print_success "Python3 is installed: $PYTHON_VERSION"

    # Check for passlib
    if python3 -c "import passlib" &> /dev/null; then
        print_success "passlib module is available"
    else
        print_warning "passlib module is not installed"
        echo "  Install with: pip install passlib"
        WARNINGS=$((WARNINGS + 1))
    fi
else
    print_error "Python3 is not installed"
    echo "  Install Python3 from: https://www.python.org/"
    ERRORS=$((ERRORS + 1))
fi
echo ""

# Check 9: Existing profiles
print_info "Checking existing profiles..."
if kubectl get profiles &> /dev/null; then
    PROFILE_COUNT=$(kubectl get profiles --no-headers 2>/dev/null | wc -l)
    if [ "$PROFILE_COUNT" -gt 0 ]; then
        print_success "Found $PROFILE_COUNT existing profile(s)"
        echo ""
        echo "  Existing profiles:"
        kubectl get profiles -o custom-columns=NAME:.metadata.name,OWNER:.spec.owner.name --no-headers | sed 's/^/    /'
    else
        print_info "No profiles found yet"
    fi
else
    print_warning "Cannot list profiles (may be due to previous errors)"
    WARNINGS=$((WARNINGS + 1))
fi
echo ""

# Summary
echo "============================================"
echo "  Summary"
echo "============================================"
echo ""

if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    print_success "All checks passed! You're ready to create profiles."
    echo ""
    echo "Next steps:"
    echo "  1. Create a user: ./create-user-and-profile.sh user@example.com username"
    echo "  2. Or manually: see QUICK_START.md"
elif [ $ERRORS -eq 0 ]; then
    print_warning "Checks completed with $WARNINGS warning(s)"
    echo ""
    echo "You can proceed but may encounter issues."
    echo "Review warnings above and fix if needed."
else
    print_error "Checks failed with $ERRORS error(s) and $WARNINGS warning(s)"
    echo ""
    echo "Please fix the errors above before creating profiles."
    echo ""
    echo "Quick fix: Install missing components:"
    echo "  # Full Kubeflow installation:"
    echo "  while ! kustomize build example | kubectl apply --server-side --force-conflicts -f -; do echo 'Retrying...'; sleep 20; done"
    echo ""
    echo "  # Or install components individually (see README.md)"
    exit 1
fi
