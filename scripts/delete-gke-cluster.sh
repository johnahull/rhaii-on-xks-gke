#!/bin/bash
# Customer-friendly GKE cluster deletion for RHAII deployments
# Provides options for complete deletion or cost-saving scale-down

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Load from environment variables if set
PROJECT_ID="${PROJECT_ID:-}"
ZONE="${ZONE:-}"
CLUSTER_NAME="${CLUSTER_NAME:-}"

show_usage() {
    cat <<EOF
========================================
RHAII GKE Cluster Deletion
========================================

Delete or scale down your GKE cluster to stop costs.

Usage: $0 [OPTIONS]

Options:
  --cluster-name <name>   Cluster name (default: from environment or "rhaii-cluster")
  --zone <zone>           Zone for cluster (default: from environment)
  --project <project>     GCP project ID (default: from environment or gcloud config)
  --scale-to-zero         Scale accelerator nodes to 0 instead of deleting (saves ~95% of costs)
  --force                 Skip confirmation prompts
  --help, -h              Show this help message

Examples:
  # Delete cluster with confirmation
  $0 --cluster-name rhaii-cluster --zone europe-west4-a

  # Scale to zero (cheaper than deletion if you'll use it again soon)
  $0 --cluster-name rhaii-cluster --zone europe-west4-a --scale-to-zero

  # Delete without confirmation (use with caution!)
  $0 --cluster-name rhaii-cluster --zone europe-west4-a --force

Cost Comparison:
  Running cluster (TPU):     ~\$132/day
  Scaled to zero:            ~\$6/day (cluster overhead only)
  Deleted:                   \$0/day

  Running cluster (GPU):     ~\$80/day
  Scaled to zero:            ~\$6/day (cluster overhead only)
  Deleted:                   \$0/day

Recommendation:
  - Scale to zero if you'll use the cluster again within 1-2 weeks
  - Delete if you're done or won't use it for a while

========================================
EOF
}

# Parse arguments
SCALE_TO_ZERO=false
FORCE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --cluster-name)
            CLUSTER_NAME="$2"
            shift 2
            ;;
        --zone)
            ZONE="$2"
            shift 2
            ;;
        --project)
            PROJECT_ID="$2"
            shift 2
            ;;
        --scale-to-zero)
            SCALE_TO_ZERO=true
            shift
            ;;
        --force)
            FORCE=true
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

# Set defaults
CLUSTER_NAME="${CLUSTER_NAME:-rhaii-cluster}"

# Set PROJECT_ID from gcloud config if not specified
if [[ -z "$PROJECT_ID" ]]; then
    PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
fi

if [[ -z "$PROJECT_ID" ]]; then
    echo -e "${RED}Error: PROJECT_ID not set${NC}"
    echo "Either:"
    echo "  1. Set via environment: export PROJECT_ID=your-project"
    echo "  2. Set gcloud config: gcloud config set project your-project"
    echo "  3. Pass as flag: --project your-project"
    exit 1
fi

# Validate required arguments
if [[ -z "$ZONE" ]]; then
    echo -e "${RED}Error: --zone is required${NC}"
    show_usage
    exit 1
fi

echo "========================================="
echo "RHAII Cluster Deletion"
echo "========================================="
echo ""

# Check if cluster exists
echo "Checking if cluster exists..."
if ! gcloud container clusters describe "$CLUSTER_NAME" --zone "$ZONE" --project "$PROJECT_ID" &> /dev/null; then
    echo -e "${RED}Error: Cluster '$CLUSTER_NAME' not found in zone $ZONE${NC}"
    echo ""
    echo "Available clusters:"
    gcloud container clusters list --project "$PROJECT_ID" 2>/dev/null || echo "No clusters found"
    exit 1
fi

# Get cluster info
CLUSTER_STATUS=$(gcloud container clusters describe "$CLUSTER_NAME" --zone "$ZONE" --project "$PROJECT_ID" --format="value(status)" 2>/dev/null)
NODE_POOLS=$(gcloud container node-pools list --cluster "$CLUSTER_NAME" --zone "$ZONE" --project "$PROJECT_ID" --format="value(name)" 2>/dev/null | tr '\n' ', ' | sed 's/,$//')

echo -e "${GREEN}✓ Cluster found${NC}"
echo ""
echo "Cluster Details:"
echo "  Name:        $CLUSTER_NAME"
echo "  Zone:        $ZONE"
echo "  Project:     $PROJECT_ID"
echo "  Status:      $CLUSTER_STATUS"
echo "  Node Pools:  $NODE_POOLS"
echo ""

# Detect accelerator type from node pools
ACCELERATOR_TYPE="unknown"
if echo "$NODE_POOLS" | grep -q "tpu"; then
    ACCELERATOR_TYPE="tpu"
elif echo "$NODE_POOLS" | grep -q "gpu"; then
    ACCELERATOR_TYPE="gpu"
fi

if [[ "$SCALE_TO_ZERO" == "true" ]]; then
    # ============================================================================
    # Scale to Zero
    # ============================================================================
    echo "========================================="
    echo "Scaling Accelerator Nodes to Zero"
    echo "========================================="
    echo ""

    if [[ "$ACCELERATOR_TYPE" == "tpu" ]]; then
        echo "This will scale the TPU node pool to 0 nodes."
        echo ""
        echo "Cost Impact:"
        echo "  Before: ~\$132/day (running)"
        echo "  After:  ~\$6/day (scaled to zero)"
        echo "  Savings: ~\$126/day"
    elif [[ "$ACCELERATOR_TYPE" == "gpu" ]]; then
        echo "This will scale the GPU node pool to 0 nodes."
        echo ""
        echo "Cost Impact:"
        echo "  Before: ~\$80/day (running)"
        echo "  After:  ~\$6/day (scaled to zero)"
        echo "  Savings: ~\$74/day"
    else
        echo "Could not detect accelerator type from node pools."
    fi

    echo ""
    echo "The cluster will remain available and can be scaled back up with:"
    echo "  gcloud container clusters resize $CLUSTER_NAME \\"
    if [[ "$ACCELERATOR_TYPE" == "tpu" ]]; then
        echo "    --node-pool tpu-pool --num-nodes 1 \\"
    else
        echo "    --node-pool gpu-pool --num-nodes 1 \\"
    fi
    echo "    --zone $ZONE --project $PROJECT_ID"
    echo ""

    if [[ "$FORCE" == "false" ]]; then
        read -p "Proceed with scaling to zero? (yes/no): " CONFIRM
        if [[ "$CONFIRM" != "yes" ]]; then
            echo "Cancelled."
            exit 0
        fi
    fi

    echo ""
    echo "Scaling accelerator node pool to 0..."

    if [[ "$ACCELERATOR_TYPE" == "tpu" ]]; then
        gcloud container clusters resize "$CLUSTER_NAME" \
            --node-pool tpu-pool \
            --num-nodes 0 \
            --zone "$ZONE" \
            --project "$PROJECT_ID" \
            --quiet
    elif [[ "$ACCELERATOR_TYPE" == "gpu" ]]; then
        gcloud container clusters resize "$CLUSTER_NAME" \
            --node-pool gpu-pool \
            --num-nodes 0 \
            --zone "$ZONE" \
            --project "$PROJECT_ID" \
            --quiet
    else
        echo -e "${YELLOW}Warning: Could not detect accelerator node pool${NC}"
        echo "You may need to scale manually. List node pools:"
        echo "  gcloud container node-pools list --cluster $CLUSTER_NAME --zone $ZONE"
    fi

    echo ""
    echo -e "${GREEN}✅ Cluster scaled to zero successfully${NC}"
    echo ""
    echo "Current cost: ~\$6/day (cluster overhead only)"
    echo "To scale back up, see the command above."

else
    # ============================================================================
    # Complete Deletion
    # ============================================================================
    echo "========================================="
    echo "Cluster Deletion"
    echo "========================================="
    echo ""

    echo -e "${RED}⚠️  WARNING: This will permanently delete the cluster!${NC}"
    echo ""
    echo "What will be deleted:"
    echo "  • GKE cluster: $CLUSTER_NAME"
    echo "  • All node pools: $NODE_POOLS"
    echo "  • All running workloads"
    echo "  • Load balancers and associated resources"
    echo ""
    echo "What will NOT be deleted:"
    echo "  • Persistent volumes (delete manually if needed)"
    echo "  • Container images in Artifact Registry"
    echo "  • Secrets stored outside the cluster"
    echo ""

    if [[ "$ACCELERATOR_TYPE" == "tpu" ]]; then
        echo "Cost savings: ~\$132/day → \$0/day"
    elif [[ "$ACCELERATOR_TYPE" == "gpu" ]]; then
        echo "Cost savings: ~\$80/day → \$0/day"
    fi

    echo ""
    echo "Alternative: Use --scale-to-zero to keep the cluster but stop costs"
    echo ""

    if [[ "$FORCE" == "false" ]]; then
        read -p "Are you sure you want to delete this cluster? Type 'delete' to confirm: " CONFIRM
        if [[ "$CONFIRM" != "delete" ]]; then
            echo "Cancelled."
            exit 0
        fi
    fi

    echo ""
    echo "Deleting cluster..."
    echo "This will take ~5-10 minutes..."
    echo ""

    gcloud container clusters delete "$CLUSTER_NAME" \
        --zone "$ZONE" \
        --project "$PROJECT_ID" \
        --quiet

    echo ""
    echo -e "${GREEN}✅ Cluster deleted successfully${NC}"
    echo ""
    echo "Cost: \$0/day"
    echo ""
    echo "To create a new cluster, run:"
    echo "  ./scripts/create-gke-cluster.sh --tpu  # or --gpu"
fi

echo ""
echo "Done!"
