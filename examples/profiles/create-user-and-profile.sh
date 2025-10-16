#!/bin/bash
#
# Script to create a new Kubeflow user with Dex authentication and Profile
#
# Usage: ./create-user-and-profile.sh <email> <username> [profile-name]
#
# Example: ./create-user-and-profile.sh alice@example.com alice alice-profile
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
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check arguments
if [ $# -lt 2 ]; then
    print_error "Usage: $0 <email> <username> [profile-name]"
    echo "Example: $0 alice@example.com alice alice-profile"
    exit 1
fi

EMAIL="$1"
USERNAME="$2"
PROFILE_NAME="${3:-kubeflow-${USERNAME}}"

# Validate email format
if [[ ! "$EMAIL" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
    print_error "Invalid email format: $EMAIL"
    exit 1
fi

# Generate a random user ID
USER_ID=$(date +%s | sha256sum | base64 | head -c 14)

print_info "Creating user with the following details:"
echo "  Email: $EMAIL"
echo "  Username: $USERNAME"
echo "  Profile Name: $PROFILE_NAME"
echo "  User ID: $USER_ID"
echo ""

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    print_error "kubectl command not found. Please install kubectl."
    exit 1
fi

# Check if Profile CRD is installed
print_info "Checking if Profile CRD is installed..."
if ! kubectl get crd profiles.kubeflow.org &> /dev/null; then
    print_error "Profile CRD is not installed!"
    echo ""
    echo "Please install the profiles component first:"
    echo "  kustomize build applications/profiles/upstream/overlays/kubeflow | kubectl apply -f -"
    echo ""
    echo "Or if using the full installation:"
    echo "  while ! kustomize build example | kubectl apply --server-side --force-conflicts -f -; do echo 'Retrying...'; sleep 20; done"
    exit 1
fi

# Check which API versions are available
if kubectl get profiles &> /dev/null; then
    print_success "Profile CRD is installed and accessible"
else
    print_error "Profile CRD exists but may not be ready. Please check profile controller:"
    echo "  kubectl get pods -n kubeflow | grep profile"
    exit 1
fi

# Check if python3 is available
if ! command -v python3 &> /dev/null; then
    print_error "python3 command not found. Please install python3."
    exit 1
fi

# Check if passlib is installed
if ! python3 -c "import passlib" &> /dev/null; then
    print_error "Python passlib module not found. Install it with: pip install passlib"
    exit 1
fi

# Prompt for password
print_info "Enter password for $EMAIL (input will be hidden):"
read -s PASSWORD
echo ""

if [ -z "$PASSWORD" ]; then
    print_error "Password cannot be empty"
    exit 1
fi

print_info "Confirm password:"
read -s PASSWORD_CONFIRM
echo ""

if [ "$PASSWORD" != "$PASSWORD_CONFIRM" ]; then
    print_error "Passwords do not match"
    exit 1
fi

# Generate password hash
print_info "Generating password hash..."
PASSWORD_HASH=$(python3 -c "from passlib.hash import bcrypt; print(bcrypt.using(rounds=12, ident='2y').hash('$PASSWORD'))")

if [ -z "$PASSWORD_HASH" ]; then
    print_error "Failed to generate password hash"
    exit 1
fi

print_success "Password hash generated"

# Create environment variable name for password
ENV_VAR_NAME="DEX_${USERNAME^^}_PASSWORD"

# Step 1: Update Dex ConfigMap
print_info "Updating Dex ConfigMap..."

# Get current Dex ConfigMap
if ! kubectl get configmap dex -n auth &> /dev/null; then
    print_error "Dex ConfigMap not found in namespace 'auth'. Is Kubeflow installed?"
    exit 1
fi

# Create a temporary file with the new user entry
cat > /tmp/new_dex_user.yaml <<EOF
    - email: $EMAIL
      hashFromEnv: $ENV_VAR_NAME
      username: $USERNAME
      userID: "$USER_ID"
EOF

print_warning "Please manually add the following to the Dex ConfigMap under staticPasswords:"
echo "---"
cat /tmp/new_dex_user.yaml
echo "---"
echo ""
print_info "Run: kubectl edit configmap dex -n auth"
echo ""
read -p "Press Enter after you've updated the ConfigMap..."

# Step 2: Update Dex passwords secret
print_info "Updating Dex passwords secret..."

if kubectl get secret dex-passwords -n auth &> /dev/null; then
    kubectl patch secret dex-passwords -n auth --type merge -p "{\"stringData\":{\"$ENV_VAR_NAME\":\"$PASSWORD_HASH\"}}"
    print_success "Dex passwords secret updated"
else
    print_warning "dex-passwords secret not found. Creating it..."
    kubectl create secret generic dex-passwords -n auth --from-literal="$ENV_VAR_NAME=$PASSWORD_HASH"
    print_success "Dex passwords secret created"
fi

# Step 3: Restart Dex deployment
print_info "Restarting Dex deployment..."
kubectl rollout restart deployment dex -n auth

print_info "Waiting for Dex to be ready..."
if kubectl wait --for=condition=Ready pods -l app=dex -n auth --timeout=180s; then
    print_success "Dex is ready"
else
    print_error "Dex failed to become ready within timeout"
    exit 1
fi

# Step 4: Create Profile
print_info "Creating Kubeflow Profile..."

cat > /tmp/profile_${USERNAME}.yaml <<EOF
apiVersion: kubeflow.org/v1
kind: Profile
metadata:
  name: $PROFILE_NAME
spec:
  owner:
    kind: User
    name: $EMAIL
  resourceQuotaSpec:
    hard:
      cpu: "4"
      memory: 8Gi
      requests.nvidia.com/gpu: "1"
      persistentvolumeclaims: "5"
      requests.storage: "50Gi"
      pods: "50"
EOF

echo ""
print_info "Profile configuration:"
echo "---"
cat /tmp/profile_${USERNAME}.yaml
echo "---"
echo ""

read -p "Do you want to apply this profile? (y/n): " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    kubectl apply -f /tmp/profile_${USERNAME}.yaml
    print_success "Profile created"

    # Wait for profile to be ready
    print_info "Waiting for profile namespace to be created..."
    sleep 5

    if kubectl get namespace $PROFILE_NAME &> /dev/null; then
        print_success "Profile namespace created: $PROFILE_NAME"
    else
        print_warning "Profile namespace not found yet. Check with: kubectl get profile $PROFILE_NAME"
    fi
else
    print_info "Profile not applied. You can apply it later with:"
    echo "  kubectl apply -f /tmp/profile_${USERNAME}.yaml"
fi

# Summary
echo ""
echo "============================================"
print_success "User creation complete!"
echo "============================================"
echo ""
echo "User Details:"
echo "  Email: $EMAIL"
echo "  Username: $USERNAME"
echo "  Profile: $PROFILE_NAME"
echo ""
echo "Next Steps:"
echo "  1. Verify profile: kubectl get profile $PROFILE_NAME"
echo "  2. Check namespace: kubectl get namespace $PROFILE_NAME"
echo "  3. Port-forward gateway: kubectl port-forward svc/istio-ingressgateway -n istio-system 8080:80"
echo "  4. Login at: http://localhost:8080"
echo "     Email: $EMAIL"
echo "     Password: (the password you entered)"
echo ""
print_info "Profile YAML saved to: /tmp/profile_${USERNAME}.yaml"
echo ""
