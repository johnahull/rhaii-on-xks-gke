#!/bin/bash
# Customer-friendly GKE cluster creation for RHAII LLM deployments
# Integrates all validation checks and provides clear guidance

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Load from environment variables if set, otherwise use defaults
# Command-line flags will override these values during argument parsing
PROJECT_ID="${PROJECT_ID:-}"
ZONE="${ZONE:-}"
CLUSTER_NAME="${CLUSTER_NAME:-rhaii-cluster}"
ACCELERATOR_TYPE="${ACCELERATOR_TYPE:-}"
DRY_RUN=false
INTERACTIVE=true
SKIP_VALIDATION=false

show_usage() {
    cat <<EOF
========================================
RHAII GKE Cluster Creation
========================================

Creates a production-ready GKE cluster for RHAII LLM deployments.

Usage: $0 --tpu|--gpu [OPTIONS]

Required (choose one):
  --tpu                   Create TPU cluster (v6e Trillium)
  --gpu                   Create GPU cluster (T4)

Optional:
  --project <project>     GCP project ID (default: from gcloud config)
  --zone <zone>           Zone for cluster (default: europe-west4-a)
  --cluster-name <name>   Cluster name (default: rhaii-cluster)
  --dry-run               Run validation only, don't create cluster
  --skip-validation       Skip pre-flight validation checks (not recommended)
  --non-interactive       Disable interactive prompts
  --help, -h              Show this help message

Examples:
  # Interactive TPU cluster creation (recommended)
  $0 --tpu

  # GPU cluster in specific zone
  $0 --gpu --zone europe-west4-a

  # Dry run to check prerequisites
  $0 --tpu --dry-run

  # Non-interactive with custom name
  $0 --gpu --cluster-name my-cluster --non-interactive

Cost Estimates:
  TPU (v6e):
    • Single-model deployment: ~\$132/day (\$3,960/month)
    • High-throughput scale-out: ~\$377/day (\$11,310/month)

  GPU (T4):
    • Single-model deployment: ~\$80/day (\$2,400/month)
    • High-throughput scale-out: ~\$228/day (\$6,840/month)

========================================
EOF
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --tpu)
            ACCELERATOR_TYPE="tpu"
            shift
            ;;
        --gpu)
            ACCELERATOR_TYPE="gpu"
            shift
            ;;
        --project)
            PROJECT_ID="$2"
            shift 2
            ;;
        --zone)
            ZONE="$2"
            shift 2
            ;;
        --cluster-name)
            CLUSTER_NAME="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --skip-validation)
            SKIP_VALIDATION=true
            shift
            ;;
        --non-interactive)
            INTERACTIVE=false
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

# Validate required arguments
if [[ -z "$ACCELERATOR_TYPE" ]]; then
    echo -e "${RED}Error: Must specify either --tpu or --gpu${NC}"
    show_usage
    exit 1
fi

# Set default zone based on accelerator
if [[ -z "$ZONE" ]]; then
    ZONE="europe-west4-a"
fi

# Get project ID from gcloud if not specified
if [[ -z "$PROJECT_ID" ]]; then
    PROJECT_ID=$(gcloud config get-value project 2>/dev/null)
    if [[ -z "$PROJECT_ID" ]]; then
        echo -e "${RED}Error: Could not determine GCP project ID${NC}"
        echo "Please run: gcloud config set project YOUR_PROJECT_ID"
        exit 1
    fi
fi

# Display configuration
echo "========================================="
echo "GKE Cluster Configuration"
echo "========================================="
echo ""
echo "Accelerator:    $ACCELERATOR_TYPE"
echo "Project:        $PROJECT_ID"
echo "Zone:           $ZONE"
echo "Cluster Name:   $CLUSTER_NAME"
echo ""

# Interactive confirmation if not in non-interactive mode
if [[ "$INTERACTIVE" == "true" ]]; then
    # Show cost estimate
    if [[ "$ACCELERATOR_TYPE" == "tpu" ]]; then
        echo "💰 Estimated Costs (TPU v6e):"
        echo "   • Single-model: ~\$132/day (\$3,960/month)"
        echo "   • Scale-out: ~\$377/day (\$11,310/month)"
    else
        echo "💰 Estimated Costs (GPU T4):"
        echo "   • Single-model: ~\$80/day (\$2,400/month)"
        echo "   • Scale-out: ~\$228/day (\$6,840/month)"
    fi
    echo ""
    echo "⏱️  Total Creation Time: ~20 minutes"
    echo ""

    read -p "Proceed with cluster creation? (yes/no): " CONFIRM
    if [[ "$CONFIRM" != "yes" && "$CONFIRM" != "y" ]]; then
        echo "Cluster creation cancelled."
        exit 0
    fi
    echo ""
fi

# ============================================================================
# Step 1: Run Validation Checks
# ============================================================================
if [[ "$SKIP_VALIDATION" == "false" ]]; then
    echo "========================================="
    echo "Step 1/4: Running Validation Checks"
    echo "========================================="
    echo ""

    # Check 1: Accelerator availability
    echo "✓ Checking accelerator availability in $ZONE..."
    if ! ./scripts/check-accelerator-availability.sh --zone "$ZONE" --type "$ACCELERATOR_TYPE" --customer > /dev/null 2>&1; then
        echo -e "${RED}❌ Accelerator not available in zone: $ZONE${NC}"
        echo ""
        echo "Suggested zones:"
        ./scripts/check-accelerator-availability.sh --type "$ACCELERATOR_TYPE" --customer | grep -A 5 "RECOMMENDATIONS"
        exit 1
    fi
    echo -e "${GREEN}✅ Accelerator available in $ZONE${NC}"
    echo ""

    # Check 2: Node pool prerequisites
    echo "✓ Checking node pool prerequisites..."
    if [[ "$ACCELERATOR_TYPE" == "tpu" ]]; then
        MACHINE_TYPE="ct6e-standard-4t"
        if ! ./scripts/check-nodepool-prerequisites.sh \
            --zone "$ZONE" \
            --machine-type "$MACHINE_TYPE" \
            --customer > /dev/null 2>&1; then
            echo -e "${RED}❌ Node pool prerequisites check failed${NC}"
            echo "Run this command for details:"
            echo "  ./scripts/check-nodepool-prerequisites.sh --zone $ZONE --machine-type $MACHINE_TYPE --customer"
            exit 1
        fi
    else
        MACHINE_TYPE="n1-standard-4"
        ACCELERATOR="nvidia-tesla-t4"
        if ! ./scripts/check-nodepool-prerequisites.sh \
            --zone "$ZONE" \
            --machine-type "$MACHINE_TYPE" \
            --accelerator "$ACCELERATOR" \
            --customer > /dev/null 2>&1; then
            echo -e "${RED}❌ Node pool prerequisites check failed${NC}"
            echo "Run this command for details:"
            echo "  ./scripts/check-nodepool-prerequisites.sh --zone $ZONE --machine-type $MACHINE_TYPE --accelerator $ACCELERATOR --customer"
            exit 1
        fi
    fi
    echo -e "${GREEN}✅ Node pool prerequisites satisfied${NC}"
    echo ""

    # Check 3: Preflight checks
    echo "✓ Running comprehensive preflight checks..."
    # We don't have a deployment path yet, so we'll check the istio-kserve/baseline-pattern as default
    DEPLOYMENT_PATH="istio-kserve/baseline-pattern"
    if ! ./scripts/preflight-check.sh \
        --deployment "$DEPLOYMENT_PATH" \
        --zone "$ZONE" \
        --accelerator "$ACCELERATOR_TYPE" \
        --project "$PROJECT_ID" \
        --customer \
        --skip-cluster > /dev/null 2>&1; then
        echo -e "${RED}❌ Preflight checks failed${NC}"
        echo "Run this command for details:"
        echo "  ./scripts/preflight-check.sh --deployment $DEPLOYMENT_PATH --zone $ZONE --accelerator $ACCELERATOR_TYPE --customer"
        exit 1
    fi
    echo -e "${GREEN}✅ All preflight checks passed${NC}"
    echo ""
fi

if [[ "$DRY_RUN" == "true" ]]; then
    echo "========================================="
    echo "✅ DRY RUN COMPLETE"
    echo "========================================="
    echo ""
    echo "All validation checks passed!"
    echo "Run without --dry-run to create the cluster."
    exit 0
fi

# ============================================================================
# Step 2: Create GKE Cluster (Control Plane)
# ============================================================================
echo "========================================="
echo "Step 2/4: Creating GKE Cluster"
echo "========================================="
echo ""
echo "Creating control plane..."
echo "This will take ~5 minutes..."
echo ""

gcloud container clusters create "$CLUSTER_NAME" \
    --zone "$ZONE" \
    --machine-type n1-standard-4 \
    --num-nodes 2 \
    --project "$PROJECT_ID" \
    --enable-ip-alias \
    --enable-autoscaling \
    --min-nodes 1 \
    --max-nodes 5 \
    --addons HorizontalPodAutoscaling,HttpLoadBalancing

echo -e "${GREEN}✅ Cluster created successfully${NC}"
echo ""

# Get credentials
echo "Configuring kubectl access..."
gcloud container clusters get-credentials "$CLUSTER_NAME" \
    --zone "$ZONE" \
    --project "$PROJECT_ID"

echo -e "${GREEN}✅ kubectl configured${NC}"
echo ""

# ============================================================================
# Step 3: Create Accelerator Node Pool
# ============================================================================
echo "========================================="
echo "Step 3/4: Creating Accelerator Node Pool"
echo "========================================="
echo ""

if [[ "$ACCELERATOR_TYPE" == "tpu" ]]; then
    echo "Creating TPU v6e node pool..."
    echo "This will take ~10-15 minutes..."
    echo ""
    echo "Note: TPU machine type ct6e-standard-4t auto-configures topology (no autoscaling)"
    echo ""

    NODE_POOL_OUTPUT=$(gcloud container node-pools create tpu-pool \
        --cluster "$CLUSTER_NAME" \
        --zone "$ZONE" \
        --machine-type ct6e-standard-4t \
        --num-nodes 1 \
        --project "$PROJECT_ID" 2>&1)
    NODE_POOL_EXIT=$?
else
    echo "Creating GPU T4 node pool..."
    echo "This will take ~5-10 minutes..."
    echo ""

    NODE_POOL_OUTPUT=$(gcloud container node-pools create gpu-pool \
        --cluster "$CLUSTER_NAME" \
        --zone "$ZONE" \
        --machine-type n1-standard-4 \
        --accelerator type=nvidia-tesla-t4,count=1 \
        --num-nodes 1 \
        --enable-autoscaling \
        --min-nodes 0 \
        --max-nodes 3 \
        --project "$PROJECT_ID" 2>&1)
    NODE_POOL_EXIT=$?
fi

# Check if node pool creation failed
if [[ $NODE_POOL_EXIT -ne 0 ]]; then
    # Check for capacity exhaustion
    if echo "$NODE_POOL_OUTPUT" | grep -qi "RESOURCE_EXHAUSTED\|exhausted.*capacity\|not available"; then
        echo -e "${RED}❌ No capacity available in $ZONE${NC}"
        echo ""
        echo "The zone is temporarily out of $ACCELERATOR_TYPE capacity for GKE node pools."
        echo "This is usually temporary and may resolve within hours."
        echo ""
        echo "Try these alternative zones with good availability:"
        echo ""

        if [[ "$ACCELERATOR_TYPE" == "tpu" ]]; then
            echo "  # US zones (lower latency from North America)"
            echo "  ./scripts/create-gke-cluster.sh --tpu --zone us-east5-a"
            echo "  ./scripts/create-gke-cluster.sh --tpu --zone us-south1-a"
            echo ""
            echo "  # Europe zones (lower latency from Europe)"
            echo "  ./scripts/create-gke-cluster.sh --tpu --zone europe-west4-b"
            echo "  ./scripts/create-gke-cluster.sh --tpu --zone europe-west4-c"
        else
            echo "  # US zones (lower latency from North America)"
            echo "  ./scripts/create-gke-cluster.sh --gpu --zone us-east4-a"
            echo "  ./scripts/create-gke-cluster.sh --gpu --zone us-central1-c"
            echo ""
            echo "  # Europe zones (lower latency from Europe)"
            echo "  ./scripts/create-gke-cluster.sh --gpu --zone europe-west4-b"
            echo "  ./scripts/create-gke-cluster.sh --gpu --zone europe-west1-b"
        fi

        echo ""
        echo "Or wait and retry the current zone:"
        echo "  ./scripts/create-gke-cluster.sh --$ACCELERATOR_TYPE --zone $ZONE"
        echo ""
        echo "Tip: Delete the partially created cluster first:"
        echo "  ./scripts/delete-gke-cluster.sh --cluster-name $CLUSTER_NAME --zone $ZONE --force"
        exit 1
    else
        # Other error - display full output
        echo -e "${RED}❌ Node pool creation failed${NC}"
        echo ""
        echo "Error output:"
        echo "$NODE_POOL_OUTPUT"
        exit 1
    fi
fi

echo -e "${GREEN}✅ Accelerator node pool created successfully${NC}"
echo ""

# ============================================================================
# Step 4: Verify Cluster
# ============================================================================
echo "========================================="
echo "Step 4/4: Verifying Cluster"
echo "========================================="
echo ""

echo "Checking cluster status..."
CLUSTER_STATUS=$(gcloud container clusters describe "$CLUSTER_NAME" --zone "$ZONE" --project "$PROJECT_ID" --format="value(status)")
echo "Cluster status: $CLUSTER_STATUS"
echo ""

echo "Checking node pools..."
kubectl get nodes
echo ""

echo -e "${GREEN}✅ Cluster verification complete${NC}"
echo ""

# ============================================================================
# Success Summary
# ============================================================================
echo "========================================="
echo "🎉 CLUSTER CREATION SUCCESSFUL!"
echo "========================================="
echo ""
echo "Cluster Details:"
echo "  Name:       $CLUSTER_NAME"
echo "  Zone:       $ZONE"
echo "  Project:    $PROJECT_ID"
echo "  Accelerator: $ACCELERATOR_TYPE"
echo ""
echo "📋 Next Steps:"
echo ""
echo "1. Install RHAII operators (~10 minutes)"
echo "   See: docs/customer-guides/operator-installation.md"
echo ""
echo "2. Deploy your workload (~10 minutes)"
if [[ "$ACCELERATOR_TYPE" == "tpu" ]]; then
    echo "   Follow: docs/customer-guides/deployment-tpu.md"
else
    echo "   Follow: docs/customer-guides/deployment-gpu.md"
fi
echo ""
echo "💰 Cost Management:"
echo "   Scale down when not in use:"
if [[ "$ACCELERATOR_TYPE" == "tpu" ]]; then
    echo "   gcloud container clusters resize $CLUSTER_NAME --node-pool tpu-pool --num-nodes 0 --zone $ZONE"
else
    echo "   gcloud container clusters resize $CLUSTER_NAME --node-pool gpu-pool --num-nodes 0 --zone $ZONE"
fi
echo ""
echo "📚 Documentation: docs/customer-guides/"
echo ""
echo "========================================="
