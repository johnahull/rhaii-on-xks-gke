#!/bin/bash
# Cost estimation calculator for RHAII LLM deployments
# Provides detailed cost breakdowns and recommendations

set -e

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

show_usage() {
    cat <<EOF
========================================
RHAII Deployment Cost Estimator
========================================

Calculates deployment costs and provides optimization recommendations.

Usage: $0 --deployment <type> --accelerator <type> [OPTIONS]

Required:
  --deployment <type>     Deployment type: single-model or scale-out
  --accelerator <type>    Accelerator type: tpu or gpu

Optional:
  --region <region>       GCP region (affects pricing, default: us-central1)
  --traffic <req/s>       Expected traffic in requests/second
  --compare               Show comparison between deployment types
  --help, -h              Show this help message

Examples:
  # Single-model TPU deployment
  $0 --deployment single-model --accelerator tpu

  # Scale-out GPU deployment with traffic estimate
  $0 --deployment scale-out --accelerator gpu --traffic 15

  # Compare deployment types
  $0 --accelerator tpu --compare

========================================
EOF
}

# Parse arguments
DEPLOYMENT_TYPE=""
ACCELERATOR_TYPE=""
REGION="us-central1"
TRAFFIC=""
COMPARE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --deployment)
            DEPLOYMENT_TYPE="$2"
            shift 2
            ;;
        --accelerator)
            ACCELERATOR_TYPE="$2"
            shift 2
            ;;
        --region)
            REGION="$2"
            shift 2
            ;;
        --traffic)
            TRAFFIC="$2"
            shift 2
            ;;
        --compare)
            COMPARE=true
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

# ============================================================================
# Cost Data (February 2026 pricing)
# ============================================================================

# TPU v6e pricing (per chip per hour)
TPU_V6E_HOURLY=1.32  # $1.32 per chip/hour in us-central1

# GPU T4 pricing (per GPU per hour)
GPU_T4_HOURLY=0.35  # $0.35 per GPU/hour in us-central1

# GKE cluster overhead (control plane + 2 standard nodes)
GKE_OVERHEAD_HOURLY=0.25  # Approximate

# ============================================================================
# Helper Functions
# ============================================================================

calculate_costs() {
    local accel_type=$1
    local deployment_type=$2

    if [[ "$accel_type" == "tpu" ]]; then
        if [[ "$deployment_type" == "single-model" ]]; then
            # 1 node, 4 chips
            CHIPS=4
            HOURLY_COST=$(echo "$CHIPS * $TPU_V6E_HOURLY + $GKE_OVERHEAD_HOURLY" | bc)
        else
            # 3 nodes, 12 chips total
            CHIPS=12
            HOURLY_COST=$(echo "$CHIPS * $TPU_V6E_HOURLY + $GKE_OVERHEAD_HOURLY" | bc)
        fi
    else
        if [[ "$deployment_type" == "single-model" ]]; then
            # 1 GPU
            GPUS=1
            HOURLY_COST=$(echo "$GPUS * $GPU_T4_HOURLY + $GKE_OVERHEAD_HOURLY" | bc)
        else
            # 3 GPUs
            GPUS=3
            HOURLY_COST=$(echo "$GPUS * $GPU_T4_HOURLY + $GKE_OVERHEAD_HOURLY" | bc)
        fi
    fi

    DAILY_COST=$(echo "$HOURLY_COST * 24" | bc)
    MONTHLY_COST=$(echo "$DAILY_COST * 30" | bc)

    # Format costs
    printf "%.2f" "$HOURLY_COST"
    echo -n " "
    printf "%.2f" "$DAILY_COST"
    echo -n " "
    printf "%.2f" "$MONTHLY_COST"
}

display_cost_breakdown() {
    local accel_type=$1
    local deployment_type=$2
    local title=$3

    echo "========================================="
    echo "$title"
    echo "========================================="
    echo ""

    # Calculate costs
    read HOURLY DAILY MONTHLY <<< $(calculate_costs "$accel_type" "$deployment_type")

    echo "Deployment Configuration:"
    if [[ "$accel_type" == "tpu" ]]; then
        if [[ "$deployment_type" == "single-model" ]]; then
            echo "  • 1 node with 4 TPU v6e chips"
            echo "  • Machine type: ct6e-standard-4t"
            echo "  • Performance: ~7-8 req/s parallel, ~1.9 req/s serial"
        else
            echo "  • 3 nodes with 12 TPU v6e chips total"
            echo "  • Machine type: ct6e-standard-4t"
            echo "  • Performance: ~25 req/s parallel, ~6.3 req/s serial"
            echo "  • Prefix caching enabled"
        fi
    else
        if [[ "$deployment_type" == "single-model" ]]; then
            echo "  • 1 node with 1 T4 GPU"
            echo "  • Machine type: n1-standard-4"
            echo "  • Performance: ~5-6 req/s parallel, ~1.5 req/s serial"
        else
            echo "  • 3 nodes with 3 T4 GPUs total"
            echo "  • Machine type: n1-standard-4"
            echo "  • Performance: ~18 req/s parallel, ~4.8 req/s serial"
            echo "  • Prefix caching enabled"
        fi
    fi
    echo ""

    echo "Cost Breakdown:"
    echo "  Hourly:   \$$HOURLY"
    echo "  Daily:    \$$DAILY"
    echo "  Monthly:  \$$MONTHLY"
    echo ""

    # Cost per request if traffic specified
    if [[ -n "$TRAFFIC" ]]; then
        REQUESTS_PER_DAY=$(echo "$TRAFFIC * 86400" | bc)
        COST_PER_1K_REQUESTS=$(echo "scale=4; ($DAILY / $REQUESTS_PER_DAY) * 1000" | bc)
        echo "At $TRAFFIC req/s:"
        printf "  Cost per 1,000 requests: \$%.4f\n" "$COST_PER_1K_REQUESTS"
        echo ""
    fi

    # Savings when scaled to zero
    SCALED_ZERO_DAILY=$(echo "scale=2; $GKE_OVERHEAD_HOURLY * 24" | bc)
    SAVINGS_DAILY=$(echo "scale=2; $DAILY - $SCALED_ZERO_DAILY" | bc)
    SAVINGS_MONTHLY=$(echo "scale=2; $MONTHLY - ($SCALED_ZERO_DAILY * 30)" | bc)

    echo "Cost Savings (scaled to 0 nodes):"
    echo "  Daily savings:    \$$SAVINGS_DAILY"
    echo "  Monthly savings:  \$$SAVINGS_MONTHLY"
    echo "  Residual cost:    \$$SCALED_ZERO_DAILY/day (GKE control plane)"
    echo ""
}

# ============================================================================
# Main Script
# ============================================================================

if [[ "$COMPARE" == "true" ]]; then
    if [[ -z "$ACCELERATOR_TYPE" ]]; then
        echo "Error: --accelerator required for comparison"
        exit 1
    fi

    echo ""
    echo "========================================"
    echo "COST COMPARISON: $ACCELERATOR_TYPE"
    echo "========================================="
    echo ""

    display_cost_breakdown "$ACCELERATOR_TYPE" "single-model" "Single-Model Deployment"
    display_cost_breakdown "$ACCELERATOR_TYPE" "scale-out" "High-Throughput Scale-Out"

    # Comparison summary
    read SM_HOURLY SM_DAILY SM_MONTHLY <<< $(calculate_costs "$ACCELERATOR_TYPE" "single-model")
    read SO_HOURLY SO_DAILY SO_MONTHLY <<< $(calculate_costs "$ACCELERATOR_TYPE" "scale-out")

    COST_MULTIPLIER=$(echo "scale=1; $SO_DAILY / $SM_DAILY" | bc)

    if [[ "$ACCELERATOR_TYPE" == "tpu" ]]; then
        PERF_MULTIPLIER=3.3
    else
        PERF_MULTIPLIER=3.2
    fi

    echo "========================================="
    echo "Summary"
    echo "========================================="
    echo ""
    echo "Scaling from single-model to scale-out:"
    echo "  Cost increase:        ${COST_MULTIPLIER}x (\$$SM_DAILY → \$$SO_DAILY/day)"
    echo "  Performance increase: ${PERF_MULTIPLIER}x throughput"
    echo "  Cost efficiency:      $(echo "scale=1; $PERF_MULTIPLIER / $COST_MULTIPLIER" | bc)x better cost/performance"
    echo ""
    echo "Recommendation:"
    if [[ -n "$TRAFFIC" ]]; then
        if (( $(echo "$TRAFFIC > 10" | bc -l) )); then
            echo "  ✅ Scale-out deployment recommended (>10 req/s traffic)"
        else
            echo "  ✅ Single-model deployment sufficient (<10 req/s traffic)"
        fi
    else
        echo "  • Single-model: Good for <10 req/s, dev/test"
        echo "  • Scale-out: Better for >10 req/s, production workloads"
    fi
    echo ""
    echo "========================================="

elif [[ -n "$DEPLOYMENT_TYPE" && -n "$ACCELERATOR_TYPE" ]]; then
    echo ""
    display_cost_breakdown "$ACCELERATOR_TYPE" "$DEPLOYMENT_TYPE" "Cost Estimate: $DEPLOYMENT_TYPE ($ACCELERATOR_TYPE)"

    echo "========================================="
    echo "Cost Optimization Tips"
    echo "========================================="
    echo ""
    echo "1. Scale to zero when not in use:"
    if [[ "$ACCELERATOR_TYPE" == "tpu" ]]; then
        echo "   gcloud container clusters resize CLUSTER --node-pool tpu-pool --num-nodes 0 --zone ZONE"
    else
        echo "   gcloud container clusters resize CLUSTER --node-pool gpu-pool --num-nodes 0 --zone ZONE"
    fi
    echo ""
    echo "2. Use HPA for auto-scaling based on traffic"
    echo ""
    echo "3. Consider scheduled scaling for predictable traffic patterns"
    echo ""
    echo "4. Monitor with: kubectl top nodes"
    echo ""
    echo "See: docs/customer-guides/"
    echo ""
    echo "========================================="
else
    show_usage
    exit 1
fi
