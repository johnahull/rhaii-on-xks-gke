#!/bin/bash
# Comprehensive pre-flight check for GKE LLM deployments
# Validates all requirements before deployment

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Track overall status
ALL_CHECKS_PASSED=true
WARNINGS_COUNT=0

show_usage() {
    cat <<EOF
=========================================
GKE LLM Deployment Pre-Flight Check
=========================================

Usage: $0 --accelerator <type> [OPTIONS]

Required (choose one):
  --accelerator <type>    Accelerator type: gpu or tpu
  --gpu                   Shorthand for --accelerator gpu
  --tpu                   Shorthand for --accelerator tpu

Optional:
  --cluster <name>        Cluster name to validate (creates if not specified)
  --zone <zone>           Zone for deployment (default: europe-west4-a for TPU, us-central1-a for GPU)
  --project <project>     GCP project ID (default: from gcloud config)
  --customer              Customer-friendly simplified output (recommended for first-time users)
  --skip-tools            Skip tool installation checks
  --skip-cluster          Skip cluster validation checks
  --detailed              Show detailed output for all checks

Examples:
  # TPU deployment check (shorthand)
  $0 --tpu --customer

  # GPU deployment check with existing cluster (explicit)
  $0 --accelerator gpu --cluster my-cluster --zone us-central1-a

  # TPU with custom zone (shorthand)
  $0 --tpu --zone us-south1-a

  # Detailed output (shorthand)
  $0 --gpu --detailed

=========================================
EOF
}

# Load from environment variables if set, otherwise use defaults
# Command-line flags will override these values during argument parsing
DEPLOYMENT_PATH="istio-kserve/caching-pattern"
CLUSTER_NAME=""
ZONE="${ZONE:-}"
ACCELERATOR_TYPE="${ACCELERATOR_TYPE:-}"
PROJECT_ID="${PROJECT_ID:-}"
CUSTOMER_MODE=false
SKIP_TOOLS=false
SKIP_CLUSTER=false
DETAILED=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --cluster)
            CLUSTER_NAME="$2"
            shift 2
            ;;
        --zone)
            ZONE="$2"
            shift 2
            ;;
        --accelerator)
            ACCELERATOR_TYPE="$2"
            shift 2
            ;;
        --gpu)
            ACCELERATOR_TYPE="gpu"
            shift
            ;;
        --tpu)
            ACCELERATOR_TYPE="tpu"
            shift
            ;;
        --project)
            PROJECT_ID="$2"
            shift 2
            ;;
        --customer)
            CUSTOMER_MODE=true
            shift
            ;;
        --skip-tools)
            SKIP_TOOLS=true
            shift
            ;;
        --skip-cluster)
            SKIP_CLUSTER=true
            shift
            ;;
        --detailed)
            DETAILED=true
            shift
            ;;
        --help|-h)
            show_usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Validate required parameters
if [[ -z "$ACCELERATOR_TYPE" ]]; then
    echo -e "${RED}Error: --accelerator is required${NC}"
    echo ""
    show_usage
    exit 1
fi

# Validate accelerator type
if [[ "$ACCELERATOR_TYPE" != "gpu" && "$ACCELERATOR_TYPE" != "tpu" ]]; then
    echo -e "${RED}Error: --accelerator must be 'gpu' or 'tpu', got: $ACCELERATOR_TYPE${NC}"
    echo ""
    show_usage
    exit 1
fi

# Set default zone based on accelerator type if not specified
if [[ -z "$ZONE" ]]; then
    if [[ "$ACCELERATOR_TYPE" == "tpu" ]]; then
        ZONE="europe-west4-a"
    else
        ZONE="us-central1-a"
    fi
fi

# Determine repository root directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DEPLOYMENT_DIR="${REPO_ROOT}/deployments/${DEPLOYMENT_PATH}"

# Validate deployment directory exists
if [[ ! -d "$DEPLOYMENT_DIR" ]]; then
    echo -e "${RED}Error: Deployment directory not found: $DEPLOYMENT_DIR${NC}"
    exit 1
fi

# Detect deployment pattern and technology stack
PATTERN_NAME=$(basename "$DEPLOYMENT_PATH")
TECH_STACK=$(dirname "$DEPLOYMENT_PATH")

# Set project ID if not specified
if [[ -z "$PROJECT_ID" ]]; then
    PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
fi

echo "========================================="
echo "GKE LLM Deployment Pre-Flight Check"
echo "========================================="
echo "Deployment: $DEPLOYMENT_PATH"
echo "Technology Stack: $TECH_STACK"
echo "Pattern: $PATTERN_NAME"
echo "Zone: $ZONE"
echo "Accelerator: $ACCELERATOR_TYPE"
echo "Project: ${PROJECT_ID:-'not set'}"
[[ -n "$CLUSTER_NAME" ]] && echo "Cluster: $CLUSTER_NAME"
echo ""

# ============================================================================
# Check 1: Required Tools
# ============================================================================
if [ "$SKIP_TOOLS" = false ]; then
    echo "========================================="
    echo "Check 1: Required Tools"
    echo "========================================="

    REQUIRED_TOOLS=("gcloud" "kubectl" "git")

    # Add stack-specific tools
    if [[ "$TECH_STACK" == "gateway-api" ]]; then
        REQUIRED_TOOLS+=("helm" "helmfile")
    fi

    for tool in "${REQUIRED_TOOLS[@]}"; do
        if command -v "$tool" &> /dev/null; then
            if [[ "$tool" == "kubectl" ]]; then
                VERSION=$(kubectl version --client --output=yaml 2>/dev/null | grep gitVersion | awk '{print $2}' || echo "installed")
            else
                VERSION=$($tool version --short 2>/dev/null || $tool --version 2>/dev/null | head -1 || echo "installed")
            fi
            echo -e "${GREEN}✅ $tool${NC} - $VERSION"
        else
            echo -e "${RED}❌ $tool - NOT FOUND${NC}"
            echo "   Install: https://cloud.google.com/sdk/docs/install (for gcloud)"
            ALL_CHECKS_PASSED=false
        fi
    done

    echo ""
fi

# ============================================================================
# Check 2: GCP Authentication and Project
# ============================================================================
echo "========================================="
echo "Check 2: GCP Authentication"
echo "========================================="

ACTIVE_ACCOUNT=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null)
if [[ -n "$ACTIVE_ACCOUNT" ]]; then
    echo -e "${GREEN}✅ Authenticated as: $ACTIVE_ACCOUNT${NC}"
else
    echo -e "${RED}❌ Not authenticated to gcloud${NC}"
    echo "   Run: gcloud auth login"
    ALL_CHECKS_PASSED=false
fi

if [[ -n "$PROJECT_ID" ]]; then
    # Verify project access
    if gcloud projects describe "$PROJECT_ID" &>/dev/null; then
        echo -e "${GREEN}✅ Project accessible: $PROJECT_ID${NC}"
    else
        echo -e "${RED}❌ Cannot access project: $PROJECT_ID${NC}"
        ALL_CHECKS_PASSED=false
    fi
else
    echo -e "${RED}❌ No project ID set${NC}"
    echo "   Run: gcloud config set project YOUR_PROJECT_ID"
    ALL_CHECKS_PASSED=false
fi

echo ""

# ============================================================================
# Check 3: IAM Permissions
# ============================================================================
echo "========================================="
echo "Check 3: IAM Permissions"
echo "========================================="

if [[ -n "$PROJECT_ID" && -n "$ACTIVE_ACCOUNT" ]]; then
    REQUIRED_ROLES=("roles/container.admin")

    USER_ROLES=$(gcloud projects get-iam-policy "$PROJECT_ID" \
        --flatten="bindings[].members" \
        --filter="bindings.members:user:$ACTIVE_ACCOUNT" \
        --format="value(bindings.role)" 2>/dev/null || echo "")

    for role in "${REQUIRED_ROLES[@]}"; do
        if echo "$USER_ROLES" | grep -q "$role\|roles/owner\|roles/editor"; then
            echo -e "${GREEN}✅ $role (or equivalent)${NC}"
        else
            echo -e "${YELLOW}⚠️  $role - NOT FOUND${NC}"
            echo "   You may need elevated permissions for cluster creation"
            ((WARNINGS_COUNT++))
        fi
    done
else
    echo -e "${YELLOW}⚠️  Skipping IAM check (authentication required)${NC}"
fi

echo ""

# ============================================================================
# Check 4: Accelerator and Zone Availability
# ============================================================================
echo "========================================="
echo "Check 4: Accelerator Availability"
echo "========================================="

# Determine machine type based on accelerator
MACHINE_TYPE=""
if [[ "$ACCELERATOR_TYPE" == "tpu" ]]; then
    MACHINE_TYPE="ct6e-standard-4t"
elif [[ "$ACCELERATOR_TYPE" == "gpu" ]]; then
    MACHINE_TYPE="n1-standard-4"
fi

# Use our existing accelerator checker
if [[ -f "$SCRIPT_DIR/check-accelerator-availability.sh" ]]; then
    if [[ -z "$PROJECT_ID" ]]; then
        echo -e "${YELLOW}⚠️  Skipping accelerator availability check (no project ID set)${NC}"
        ((WARNINGS_COUNT++))
    else
        echo "Running accelerator availability check for $ACCELERATOR_TYPE in $ZONE..."

        # Call checker with specific accelerator type (pass PROJECT_ID)
        CHECKER_OUTPUT=$(PROJECT="$PROJECT_ID" "$SCRIPT_DIR/check-accelerator-availability.sh" --zone "$ZONE" --type "$ACCELERATOR_TYPE" 2>&1)

        # Check for GKE availability
        if echo "$CHECKER_OUTPUT" | grep -q "✅ GKE is available"; then
            echo -e "${GREEN}✅ GKE is available in $ZONE${NC}"
        else
            echo -e "${RED}❌ GKE is not available in $ZONE${NC}"
            ALL_CHECKS_PASSED=false
        fi

        # Check for specific accelerator availability
        if [[ "$ACCELERATOR_TYPE" == "tpu" ]]; then
            if echo "$CHECKER_OUTPUT" | grep -q "✅ TPU .* is SUPPORTED"; then
                echo -e "${GREEN}✅ TPU accelerators available in $ZONE${NC}"
                # Show which TPU types are supported
                echo "$CHECKER_OUTPUT" | grep "✅ TPU" | sed 's/^/   /'
            else
                echo -e "${RED}❌ No TPU accelerators available in $ZONE${NC}"
                ALL_CHECKS_PASSED=false
            fi
        elif [[ "$ACCELERATOR_TYPE" == "gpu" ]]; then
            if echo "$CHECKER_OUTPUT" | grep -q "GPU is SUPPORTED"; then
                echo -e "${GREEN}✅ GPU accelerators available in $ZONE${NC}"
                # Show which GPU types are supported
                echo "$CHECKER_OUTPUT" | grep "✅ NVIDIA" | sed 's/^/   /'
            else
                echo -e "${RED}❌ No GPU accelerators available in $ZONE${NC}"
                ALL_CHECKS_PASSED=false
            fi
        fi
    fi
else
    echo -e "${YELLOW}⚠️  Accelerator checker script not found${NC}"
    ((WARNINGS_COUNT++))
fi

echo ""

# ============================================================================
# Check 5: Node Pool Prerequisites
# ============================================================================
echo "========================================="
echo "Check 5: Node Pool Prerequisites"
echo "========================================="

if [[ -n "$MACHINE_TYPE" && -f "$SCRIPT_DIR/check-nodepool-prerequisites.sh" ]]; then
    echo "Running comprehensive node pool validation..."

    # Build prerequisites check command
    PREREQ_CMD="$SCRIPT_DIR/check-nodepool-prerequisites.sh --zone $ZONE --machine-type $MACHINE_TYPE"

    if [[ "$ACCELERATOR_TYPE" == "gpu" ]]; then
        PREREQ_CMD="$PREREQ_CMD --accelerator nvidia-tesla-t4"
    elif [[ "$ACCELERATOR_TYPE" == "tpu" ]]; then
        PREREQ_CMD="$PREREQ_CMD --tpu-topology 2x2x1"
    fi

    [[ -n "$CLUSTER_NAME" ]] && PREREQ_CMD="$PREREQ_CMD --cluster $CLUSTER_NAME"
    [[ -n "$PROJECT_ID" ]] && PREREQ_CMD="$PREREQ_CMD --project $PROJECT_ID"

    if $PREREQ_CMD 2>&1 | grep -q "All checks PASSED"; then
        echo -e "${GREEN}✅ Node pool prerequisites validated${NC}"
    else
        echo -e "${RED}❌ Node pool prerequisites check failed${NC}"
        echo "   Run manually for details: $PREREQ_CMD"
        ALL_CHECKS_PASSED=false
    fi
else
    echo -e "${YELLOW}⚠️  Node pool prerequisites checker not found${NC}"
    ((WARNINGS_COUNT++))
fi

echo ""

# ============================================================================
# Check 6: Cluster Validation (if cluster specified)
# ============================================================================
if [[ -n "$CLUSTER_NAME" && "$SKIP_CLUSTER" = false ]]; then
    echo "========================================="
    echo "Check 6: Cluster Validation"
    echo "========================================="

    # Check if cluster exists
    if gcloud container clusters describe "$CLUSTER_NAME" --zone="$ZONE" --project="$PROJECT_ID" &>/dev/null; then
        echo -e "${GREEN}✅ Cluster $CLUSTER_NAME exists in $ZONE${NC}"

        # Get cluster credentials
        if gcloud container clusters get-credentials "$CLUSTER_NAME" --zone="$ZONE" --project="$PROJECT_ID" &>/dev/null; then
            echo -e "${GREEN}✅ Cluster credentials configured${NC}"

            # Check cluster status
            CLUSTER_STATUS=$(gcloud container clusters describe "$CLUSTER_NAME" --zone="$ZONE" --project="$PROJECT_ID" --format="value(status)" 2>/dev/null)
            if [[ "$CLUSTER_STATUS" == "RUNNING" ]]; then
                echo -e "${GREEN}✅ Cluster status: RUNNING${NC}"
            else
                echo -e "${YELLOW}⚠️  Cluster status: $CLUSTER_STATUS${NC}"
                ((WARNINGS_COUNT++))
            fi

            # Check Gateway API CRDs
            if kubectl get crd gateways.gateway.networking.k8s.io &>/dev/null; then
                echo -e "${GREEN}✅ Gateway API CRDs installed${NC}"
            else
                echo -e "${YELLOW}⚠️  Gateway API CRDs not found${NC}"
                echo "   May need to enable GKE Gateway controller"
                ((WARNINGS_COUNT++))
            fi

            # Stack-specific checks
            if [[ "$TECH_STACK" == "istio-kserve" ]]; then
                # Check for Istio
                if kubectl get namespace istio-system &>/dev/null; then
                    echo -e "${GREEN}✅ Istio namespace found${NC}"
                else
                    echo -e "${YELLOW}⚠️  Istio not installed${NC}"
                    ((WARNINGS_COUNT++))
                fi

                # Check for KServe CRDs
                if kubectl get crd llminferenceservices.llm.kserve.io &>/dev/null; then
                    echo -e "${GREEN}✅ KServe LLMInferenceService CRD found${NC}"
                else
                    echo -e "${YELLOW}⚠️  KServe CRDs not found${NC}"
                    ((WARNINGS_COUNT++))
                fi
            fi

        else
            echo -e "${RED}❌ Failed to get cluster credentials${NC}"
            ALL_CHECKS_PASSED=false
        fi
    else
        echo -e "${YELLOW}⚠️  Cluster $CLUSTER_NAME not found in $ZONE${NC}"
        echo "   Will be created during deployment"
    fi

    echo ""
fi

# ============================================================================
# Final Summary
# ============================================================================
echo "========================================="
echo "Pre-Flight Check Summary"
echo "========================================="
echo ""

if [ "$ALL_CHECKS_PASSED" = true ]; then
    if [ "$WARNINGS_COUNT" -eq 0 ]; then
        echo -e "${GREEN}✅ ALL CHECKS PASSED!${NC}"
        echo ""
        echo "You are ready to proceed with deployment."
    else
        echo -e "${YELLOW}✅ CRITICAL CHECKS PASSED with $WARNINGS_COUNT warning(s)${NC}"
        echo ""
        echo "You can proceed with deployment, but review warnings above."
    fi


else
    echo -e "${RED}❌ SOME CHECKS FAILED!${NC}"
    echo ""
    echo "Please resolve the issues above before proceeding with deployment."
    echo ""
    echo "Common fixes:"
    echo "  • Install missing tools"
    echo "  • Run: gcloud auth login"
    echo "  • Run: gcloud config set project YOUR_PROJECT_ID"
    echo "  • Request IAM permissions from project admin"
    echo "  • Create required secret files"
    exit 1
fi

# Customer-friendly summary
if [ "$CUSTOMER_MODE" = true ]; then
    echo ""
    echo "========================================="
    echo "✅ READY TO PROCEED"
    echo "========================================="
    echo ""
    echo "📋 Next Steps:"
    echo ""
    echo "1. Create GKE Cluster (~15 minutes)"
    echo "   ./scripts/create-gke-cluster.sh --${ACCELERATOR_TYPE}"
    echo ""
    echo "2. Install Operators via RHAII on XKS (~10 minutes)"
    echo "   Repository: https://github.com/opendatahub-io/rhaii-on-xks"
    echo "   Guide: docs/operator-installation.md"
    echo ""
    echo "3. Deploy Your Workload (~10 minutes)"

    if [[ "$ACCELERATOR_TYPE" == "tpu" ]]; then
        echo "   Follow: docs/deployment-tpu.md"
    else
        echo "   Follow: docs/deployment-gpu.md"
    fi

    echo ""
    echo "⏱️  Total Time: ~50 minutes for complete deployment"
    echo ""
    echo "📚 For detailed guides, see: docs/"
fi

echo ""
echo "========================================="
