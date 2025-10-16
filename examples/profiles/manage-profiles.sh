#!/bin/bash
#
# Script to manage Kubeflow profiles
#
# Usage: ./manage-profiles.sh [command]
#
# Commands:
#   list           - List all profiles
#   describe <name> - Describe a specific profile
#   quota <name>   - Show resource quota for a profile
#   users <name>   - List users with access to a profile
#   grant <profile> <user> <role> - Grant user access to profile
#   delete <name>  - Delete a profile (with confirmation)
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

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    print_error "kubectl command not found. Please install kubectl."
    exit 1
fi

# Function to list all profiles
list_profiles() {
    print_info "Listing all Kubeflow profiles..."
    echo ""

    if ! kubectl get profiles &> /dev/null; then
        print_error "Unable to list profiles. Are you connected to the cluster?"
        exit 1
    fi

    echo "PROFILE NAME                  OWNER                           AGE"
    echo "============================================================================"

    kubectl get profiles -o custom-columns=NAME:.metadata.name,OWNER:.spec.owner.name,AGE:.metadata.creationTimestamp --no-headers | while read -r name owner age; do
        printf "%-30s %-30s %s\n" "$name" "$owner" "$(date -d "$age" +%Y-%m-%d 2>/dev/null || echo "$age")"
    done

    echo ""
    print_info "Total profiles: $(kubectl get profiles --no-headers 2>/dev/null | wc -l)"
}

# Function to describe a profile
describe_profile() {
    local profile_name="$1"

    if [ -z "$profile_name" ]; then
        print_error "Profile name required"
        echo "Usage: $0 describe <profile-name>"
        exit 1
    fi

    if ! kubectl get profile "$profile_name" &> /dev/null; then
        print_error "Profile '$profile_name' not found"
        exit 1
    fi

    print_info "Profile: $profile_name"
    echo ""
    kubectl get profile "$profile_name" -o yaml
}

# Function to show resource quota
show_quota() {
    local profile_name="$1"

    if [ -z "$profile_name" ]; then
        print_error "Profile name required"
        echo "Usage: $0 quota <profile-name>"
        exit 1
    fi

    if ! kubectl get profile "$profile_name" &> /dev/null; then
        print_error "Profile '$profile_name' not found"
        exit 1
    fi

    print_info "Resource quota for profile: $profile_name"
    echo ""

    # Get quota from profile spec
    echo "=== Profile Configuration ==="
    kubectl get profile "$profile_name" -o jsonpath='{.spec.resourceQuotaSpec.hard}' | jq '.' 2>/dev/null || echo "No resource quota configured"
    echo ""

    # Get actual quota in namespace
    if kubectl get namespace "$profile_name" &> /dev/null; then
        echo "=== Actual Usage ==="
        kubectl describe resourcequota -n "$profile_name" 2>/dev/null || echo "No resource quota found in namespace"
    else
        print_warning "Namespace '$profile_name' not found"
    fi
}

# Function to list users with access
list_users() {
    local profile_name="$1"

    if [ -z "$profile_name" ]; then
        print_error "Profile name required"
        echo "Usage: $0 users <profile-name>"
        exit 1
    fi

    if ! kubectl get profile "$profile_name" &> /dev/null; then
        print_error "Profile '$profile_name' not found"
        exit 1
    fi

    print_info "Users with access to profile: $profile_name"
    echo ""

    # Get profile owner
    echo "=== Profile Owner ==="
    kubectl get profile "$profile_name" -o jsonpath='{.spec.owner.name}'
    echo ""
    echo ""

    # Get RoleBindings in the namespace
    if kubectl get namespace "$profile_name" &> /dev/null; then
        echo "=== Additional Users (RoleBindings) ==="
        kubectl get rolebinding -n "$profile_name" -o json | jq -r '.items[] | select(.subjects != null) | .subjects[] | select(.kind == "User") | "\(.name) (Role: \(.apiGroup))"' 2>/dev/null || echo "No additional users found"
    else
        print_warning "Namespace '$profile_name' not found"
    fi
}

# Function to grant user access
grant_access() {
    local profile_name="$1"
    local user_email="$2"
    local role="${3:-kubeflow-edit}"

    if [ -z "$profile_name" ] || [ -z "$user_email" ]; then
        print_error "Profile name and user email required"
        echo "Usage: $0 grant <profile-name> <user-email> [role]"
        echo "Roles: kubeflow-admin, kubeflow-edit (default), kubeflow-view"
        exit 1
    fi

    if ! kubectl get profile "$profile_name" &> /dev/null; then
        print_error "Profile '$profile_name' not found"
        exit 1
    fi

    if ! kubectl get namespace "$profile_name" &> /dev/null; then
        print_error "Namespace '$profile_name' not found"
        exit 1
    fi

    # Validate role
    case "$role" in
        kubeflow-admin|kubeflow-edit|kubeflow-view)
            ;;
        *)
            print_error "Invalid role: $role"
            echo "Valid roles: kubeflow-admin, kubeflow-edit, kubeflow-view"
            exit 1
            ;;
    esac

    print_info "Granting $role access to $user_email for profile $profile_name..."

    # Create RoleBinding
    kubectl create rolebinding "user-$(echo $user_email | tr '@.' '--')-$role" \
        -n "$profile_name" \
        --clusterrole="$role" \
        --user="$user_email" \
        --dry-run=client -o yaml | kubectl apply -f -

    print_success "Access granted"
}

# Function to delete a profile
delete_profile() {
    local profile_name="$1"

    if [ -z "$profile_name" ]; then
        print_error "Profile name required"
        echo "Usage: $0 delete <profile-name>"
        exit 1
    fi

    if ! kubectl get profile "$profile_name" &> /dev/null; then
        print_error "Profile '$profile_name' not found"
        exit 1
    fi

    print_warning "This will delete the profile and ALL resources in the namespace '$profile_name'"
    print_warning "This action CANNOT be undone!"
    echo ""

    read -p "Type the profile name to confirm deletion: " confirm

    if [ "$confirm" != "$profile_name" ]; then
        print_error "Profile name does not match. Aborting."
        exit 1
    fi

    print_info "Deleting profile $profile_name..."
    kubectl delete profile "$profile_name"

    print_success "Profile deleted"
}

# Main command dispatcher
COMMAND="${1:-help}"

case "$COMMAND" in
    list)
        list_profiles
        ;;
    describe)
        describe_profile "$2"
        ;;
    quota)
        show_quota "$2"
        ;;
    users)
        list_users "$2"
        ;;
    grant)
        grant_access "$2" "$3" "$4"
        ;;
    delete)
        delete_profile "$2"
        ;;
    help|*)
        echo "Kubeflow Profile Management Script"
        echo ""
        echo "Usage: $0 [command] [arguments]"
        echo ""
        echo "Commands:"
        echo "  list                              - List all profiles"
        echo "  describe <profile-name>           - Show detailed profile information"
        echo "  quota <profile-name>              - Show resource quota and usage"
        echo "  users <profile-name>              - List users with access to profile"
        echo "  grant <profile> <email> [role]    - Grant user access (default: kubeflow-edit)"
        echo "  delete <profile-name>             - Delete a profile (requires confirmation)"
        echo "  help                              - Show this help message"
        echo ""
        echo "Examples:"
        echo "  $0 list"
        echo "  $0 describe alice-profile"
        echo "  $0 quota alice-profile"
        echo "  $0 grant alice-profile bob@example.com kubeflow-edit"
        echo "  $0 delete old-profile"
        ;;
esac
