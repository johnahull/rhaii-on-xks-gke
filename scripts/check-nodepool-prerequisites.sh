#!/bin/bash
# Pre-flight check for GKE TPU/GPU node pool creation
# Validates zone, accelerator, machine type, quota, and cluster compatibility

set -e

# Load from environment variables if set
# Command-line flags will override these values during argument parsing
PROJECT_ID="${PROJECT_ID:-}"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

show_usage() {
    cat <<EOF
========================================
GKE Node Pool Prerequisites Checker
========================================

Validates everything needed before creating a TPU/GPU node pool.

Usage: $0 --zone <zone> --machine-type <type> [OPTIONS]

Required:
  --zone <zone>              Zone for the node pool
  --machine-type <type>      Machine type (e.g., ct6e-standard-4t, n1-standard-4)

Optional:
  --cluster <name>           Cluster name (validates cluster compatibility)
  --accelerator <type>       For GPUs: nvidia-tesla-t4, nvidia-tesla-a100, etc.
  --tpu-topology <topology>  For TPUs: 2x2x1, 2x2x2, etc.
  --project <project>        GCP project (default: from environment or gcloud config)
  --customer                 Customer-friendly output with quota guidance
  --test-capacity            Test capacity by creating test instance (experimental)
                             Note: For TPUs, tests standalone VM capacity, not GKE node pool capacity

Examples:
  # Check TPU v6e node pool prerequisites
  $0 --zone europe-west4-a --machine-type ct6e-standard-4t --tpu-topology 2x2x1

  # Check GPU node pool prerequisites
  $0 --zone us-central1-a --machine-type n1-standard-4 --accelerator nvidia-tesla-t4

  # Check with existing cluster
  $0 --zone europe-west4-a --machine-type ct6e-standard-4t --cluster my-cluster

========================================
EOF
}

# Parse arguments (environment variables used as defaults if not provided via flags)
ZONE="${ZONE:-}"
MACHINE_TYPE=""
CLUSTER="${CLUSTER_NAME:-}"
ACCELERATOR=""
TPU_TOPOLOGY=""
CUSTOMER_MODE=false
TEST_CAPACITY=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --zone)
            ZONE="$2"
            shift 2
            ;;
        --machine-type)
            MACHINE_TYPE="$2"
            shift 2
            ;;
        --cluster)
            CLUSTER="$2"
            shift 2
            ;;
        --accelerator)
            ACCELERATOR="$2"
            shift 2
            ;;
        --tpu-topology)
            TPU_TOPOLOGY="$2"
            shift 2
            ;;
        --project)
            PROJECT_ID="$2"
            shift 2
            ;;
        --customer)
            CUSTOMER_MODE=true
            shift
            ;;
        --test-capacity)
            TEST_CAPACITY=true
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

# Set PROJECT_ID from gcloud config if not specified
if [[ -z "$PROJECT_ID" ]]; then
    PROJECT_ID=$(gcloud config get-value project 2>/dev/null || echo "")
fi

if [[ -z "$PROJECT_ID" || "$PROJECT_ID" == "YOUR_PROJECT" ]]; then
    echo "Error: PROJECT_ID not set. Either:"
    echo "  1. Set via environment: export PROJECT_ID=your-project"
    echo "  2. Set gcloud config: gcloud config set project your-project"
    echo "  3. Pass as flag: --project your-project"
    exit 1
fi

# Validate required arguments
if [[ -z "$ZONE" || -z "$MACHINE_TYPE" ]]; then
    echo "Error: --zone and --machine-type are required"
    show_usage
    exit 1
fi

# Detect if this is TPU or GPU based on machine type
IS_TPU=false
IS_GPU=false

if [[ "$MACHINE_TYPE" =~ ^ct[0-9] ]]; then
    IS_TPU=true
elif [[ -n "$ACCELERATOR" ]]; then
    IS_GPU=true
else
    # Try to detect from machine type naming
    if [[ "$MACHINE_TYPE" =~ ^(a2-|g2-|a3-) ]]; then
        IS_GPU=true
    else
        echo "Warning: Cannot determine if this is TPU or GPU. Specify --accelerator for GPUs."
    fi
fi

echo "========================================="
echo "GKE Node Pool Prerequisites Check"
echo "========================================="
echo "Project: $PROJECT_ID"
echo "Zone: $ZONE"
echo "Machine Type: $MACHINE_TYPE"
[[ -n "$CLUSTER" ]] && echo "Cluster: $CLUSTER"
[[ -n "$ACCELERATOR" ]] && echo "Accelerator: $ACCELERATOR"
[[ -n "$TPU_TOPOLOGY" ]] && echo "TPU Topology: $TPU_TOPOLOGY"
echo "Type: $([ "$IS_TPU" = true ] && echo "TPU" || echo "GPU")"
echo ""

ALL_CHECKS_PASSED=true

# ============================================================================
# Check 1: GKE Availability in Zone
# ============================================================================
echo "========================================="
echo "Check 1: GKE Availability in Zone"
echo "========================================="

if gcloud container get-server-config --zone=$ZONE --project=$PROJECT_ID &> /dev/null; then
    echo -e "${GREEN}✅ GKE is available in $ZONE${NC}"

    # Get GKE version
    GKE_VERSION=$(gcloud container get-server-config --zone=$ZONE --project=$PROJECT_ID --format="value(channels[0].defaultVersion)" 2>/dev/null || echo "unknown")
    echo "   Latest GKE version: $GKE_VERSION"
else
    echo -e "${RED}❌ GKE is NOT available in $ZONE${NC}"
    ALL_CHECKS_PASSED=false
fi
echo ""

# ============================================================================
# Check 2: Machine Type Availability
# ============================================================================
echo "========================================="
echo "Check 2: Machine Type Availability"
echo "========================================="

MACHINE_CHECK=$(gcloud compute machine-types describe $MACHINE_TYPE --zone=$ZONE --project=$PROJECT_ID 2>&1)
if echo "$MACHINE_CHECK" | grep -q "name: $MACHINE_TYPE"; then
    echo -e "${GREEN}✅ Machine type $MACHINE_TYPE is available in $ZONE${NC}"

    # Extract details
    CPUS=$(echo "$MACHINE_CHECK" | grep "guestCpus:" | awk '{print $2}')
    MEMORY=$(echo "$MACHINE_CHECK" | grep "memoryMb:" | awk '{print $2}')
    MEMORY_GB=$((MEMORY / 1024))
    DESCRIPTION=$(echo "$MACHINE_CHECK" | grep "^description:" | sed 's/description: *//')

    echo "   CPUs: $CPUS"
    echo "   Memory: ${MEMORY_GB} GB"

    # Show description if available (contains GPU/TPU info)
    if [[ -n "$DESCRIPTION" ]]; then
        echo "   Description: $DESCRIPTION"
    fi

    # Validate machine type compatibility with accelerator
    if [ "$IS_TPU" = true ]; then
        # Validate TPU machine type naming
        if [[ ! "$MACHINE_TYPE" =~ ^ct[0-9] ]]; then
            echo -e "${YELLOW}⚠️  Warning: Machine type doesn't match TPU naming pattern (ct*)${NC}"
            echo "   TPU machine types should start with ct6e, ct5e, or ct5p"
        fi

        # Extract chip count from machine type name (e.g., ct6e-standard-4t -> 4)
        if [[ "$MACHINE_TYPE" =~ -([0-9]+)t?(-tpu)?$ ]]; then
            DETECTED_CHIPS="${BASH_REMATCH[1]}"
            echo "   Detected TPU chips: $DETECTED_CHIPS (from machine type name)"
        fi

    elif [ "$IS_GPU" = true ] && [[ -n "$ACCELERATOR" ]]; then
        # Check if machine type description mentions the accelerator
        if [[ -n "$DESCRIPTION" ]] && echo "$DESCRIPTION" | grep -qi "$(echo $ACCELERATOR | sed 's/nvidia-//;s/-/ /g')"; then
            echo -e "${GREEN}✅ Machine type description confirms GPU compatibility${NC}"
        elif [[ "$MACHINE_TYPE" =~ ^(a2-|g2-|a3-) ]]; then
            # GPU-optimized machine types (GPUs are integrated)
            echo "   Note: GPU-optimized machine type (integrated GPUs)"
        else
            # Standard machine type + separate accelerator
            echo "   Note: Standard machine type (GPU attached separately via --accelerator)"
        fi
    fi
else
    echo -e "${RED}❌ Machine type $MACHINE_TYPE is NOT available in $ZONE${NC}"
    echo "   Error: $MACHINE_CHECK"
    ALL_CHECKS_PASSED=false
fi
echo ""

# ============================================================================
# Check 3: Accelerator Availability (GPU or TPU)
# ============================================================================
echo "========================================="
echo "Check 3: Accelerator Availability"
echo "========================================="

if [ "$IS_TPU" = true ]; then
    # Check TPU accelerator type
    TPU_VERSION=""
    if [[ "$MACHINE_TYPE" =~ ct6e ]]; then
        TPU_VERSION="tpu-v6e"
    elif [[ "$MACHINE_TYPE" =~ ct5e ]]; then
        TPU_VERSION="tpu-v5e"
    elif [[ "$MACHINE_TYPE" =~ ct5p ]]; then
        TPU_VERSION="tpu-v5p"
    fi

    if [[ -n "$TPU_VERSION" ]]; then
        TPU_CHECK=$(gcloud compute accelerator-types list --filter="name:$TPU_VERSION AND zone:$ZONE" --project=$PROJECT_ID 2>&1)
        if echo "$TPU_CHECK" | grep -q "$ZONE"; then
            echo -e "${GREEN}✅ TPU $TPU_VERSION is available in $ZONE${NC}"
        else
            echo -e "${RED}❌ TPU $TPU_VERSION is NOT available in $ZONE${NC}"
            ALL_CHECKS_PASSED=false
        fi
    else
        echo -e "${YELLOW}⚠️  Could not determine TPU version from machine type${NC}"
    fi

elif [ "$IS_GPU" = true ]; then
    # Check GPU accelerator type
    if [[ -n "$ACCELERATOR" ]]; then
        GPU_CHECK=$(gcloud compute accelerator-types list --filter="name:$ACCELERATOR AND zone:$ZONE" --project=$PROJECT_ID 2>&1)
        if echo "$GPU_CHECK" | grep -q "$ZONE"; then
            echo -e "${GREEN}✅ GPU $ACCELERATOR is available in $ZONE${NC}"
        else
            echo -e "${RED}❌ GPU $ACCELERATOR is NOT available in $ZONE${NC}"
            ALL_CHECKS_PASSED=false
        fi
    else
        echo -e "${YELLOW}⚠️  No --accelerator specified, skipping GPU check${NC}"
    fi
fi
echo ""

# ============================================================================
# Check 4: TPU Topology Validation (TPU only)
# ============================================================================
if [ "$IS_TPU" = true ] && [[ -n "$TPU_TOPOLOGY" ]]; then
    echo "========================================="
    echo "Check 4: TPU Topology Validation"
    echo "========================================="

    # Use chip count detected in Check 2 (or extract if not already set)
    CHIP_COUNT="${DETECTED_CHIPS:-}"
    if [[ -z "$CHIP_COUNT" ]] && [[ "$MACHINE_TYPE" =~ -([0-9]+)t?$ ]]; then
        CHIP_COUNT="${BASH_REMATCH[1]}"
    fi

    # Calculate topology chip count
    IFS='x' read -ra TOPO <<< "$TPU_TOPOLOGY"
    TOPO_CHIPS=$((${TOPO[0]} * ${TOPO[1]} * ${TOPO[2]}))

    if [[ "$CHIP_COUNT" == "$TOPO_CHIPS" ]]; then
        echo -e "${GREEN}✅ Topology $TPU_TOPOLOGY matches $CHIP_COUNT-chip machine type${NC}"
    else
        echo -e "${RED}❌ Topology mismatch: $TPU_TOPOLOGY = $TOPO_CHIPS chips, but $MACHINE_TYPE requires $CHIP_COUNT chips${NC}"
        echo "   Suggested topology for $CHIP_COUNT chips:"
        case $CHIP_COUNT in
            1) echo "   (omit --tpu-topology flag)" ;;
            4) echo "   --tpu-topology=2x2x1" ;;
            8) echo "   --tpu-topology=2x2x2" ;;
            16) echo "   --tpu-topology=2x2x4 or 4x4x1" ;;
            32) echo "   --tpu-topology=4x4x2" ;;
            64) echo "   --tpu-topology=4x4x4" ;;
            128) echo "   --tpu-topology=8x8x2" ;;
            256) echo "   --tpu-topology=8x8x4" ;;
        esac
        ALL_CHECKS_PASSED=false
    fi
    echo ""
fi

# ============================================================================
# Check 5: Quota Availability
# ============================================================================
echo "========================================="
echo "Check 5: Quota Availability"
echo "========================================="

# Extract region from zone (us-central1-a -> us-central1)
REGION=$(echo $ZONE | sed 's/-[^-]*$//')

if [ "$IS_GPU" = true ] && [[ -n "$ACCELERATOR" ]]; then
    # Map accelerator type to quota metric
    QUOTA_METRIC=""
    case "$ACCELERATOR" in
        nvidia-tesla-t4) QUOTA_METRIC="NVIDIA_T4_GPUS" ;;
        nvidia-tesla-a100) QUOTA_METRIC="NVIDIA_A100_GPUS" ;;
        nvidia-a100-80gb) QUOTA_METRIC="NVIDIA_A100_80GB_GPUS" ;;
        nvidia-l4) QUOTA_METRIC="NVIDIA_L4_GPUS" ;;
        nvidia-h100-80gb) QUOTA_METRIC="NVIDIA_H100_GPUS" ;;
        nvidia-h100-mega-80gb) QUOTA_METRIC="NVIDIA_H100_MEGA_GPUS" ;;
        *) QUOTA_METRIC="" ;;
    esac

    if [[ -n "$QUOTA_METRIC" ]]; then
        echo "Checking GPU quota in region $REGION..."

        # Get quota information
        QUOTA_BLOCK=$(gcloud compute regions describe $REGION --project=$PROJECT_ID 2>&1 | \
            grep -B1 -A1 "metric: $QUOTA_METRIC$")

        if [[ -n "$QUOTA_BLOCK" ]]; then
            QUOTA_LIMIT=$(echo "$QUOTA_BLOCK" | grep "limit:" | sed 's/.*limit: *//' | awk '{printf "%.0f", $1}')
            QUOTA_USAGE=$(echo "$QUOTA_BLOCK" | grep "usage:" | sed 's/.*usage: *//' | awk '{printf "%.0f", $1}')

            # Calculate available quota (handle empty values)
            if [[ -z "$QUOTA_LIMIT" ]] || [[ -z "$QUOTA_USAGE" ]]; then
                echo -e "${YELLOW}⚠️  Could not parse quota information${NC}"
                echo "   Manual check recommended"
            else
                QUOTA_AVAIL=$((QUOTA_LIMIT - QUOTA_USAGE))

                if [[ "$QUOTA_LIMIT" -eq 0 ]]; then
                    echo -e "${RED}❌ GPU quota is ZERO for $ACCELERATOR in $REGION${NC}"
                    echo "   Metric: $QUOTA_METRIC"
                    echo "   You must request a quota increase before deployment"
                    echo "   Request at: https://console.cloud.google.com/iam-admin/quotas"
                    ALL_CHECKS_PASSED=false
                elif [[ "$QUOTA_AVAIL" -le 0 ]]; then
                    echo -e "${RED}❌ GPU quota EXHAUSTED for $ACCELERATOR in $REGION${NC}"
                    echo "   Metric: $QUOTA_METRIC"
                    echo "   Limit: $QUOTA_LIMIT | Usage: $QUOTA_USAGE | Available: $QUOTA_AVAIL"
                    echo "   Either request quota increase or delete existing instances"
                    ALL_CHECKS_PASSED=false
                elif [[ "$QUOTA_AVAIL" -le 2 ]]; then
                    echo -e "${YELLOW}⚠️  GPU quota is LOW for $ACCELERATOR in $REGION${NC}"
                    echo "   Metric: $QUOTA_METRIC"
                    echo "   Limit: $QUOTA_LIMIT | Usage: $QUOTA_USAGE | Available: $QUOTA_AVAIL"
                    echo "   Consider requesting increase for production deployments"
                else
                    echo -e "${GREEN}✅ GPU quota available for $ACCELERATOR in $REGION${NC}"
                    echo "   Metric: $QUOTA_METRIC"
                    echo "   Limit: $QUOTA_LIMIT | Usage: $QUOTA_USAGE | Available: $QUOTA_AVAIL"
                fi
            fi
        else
            echo -e "${YELLOW}⚠️  Could not find quota metric: $QUOTA_METRIC${NC}"
            echo "   Manual check recommended: https://console.cloud.google.com/iam-admin/quotas"
        fi
    else
        echo -e "${YELLOW}⚠️  Unknown accelerator type for quota check: $ACCELERATOR${NC}"
        echo "   Manual check recommended: https://console.cloud.google.com/iam-admin/quotas"
    fi

elif [ "$IS_TPU" = true ]; then
    # TPU quotas are more complex (pod-level quotas)
    echo -e "${YELLOW}⚠️  TPU quota check requires manual verification${NC}"
    echo "   TPU quotas are typically at pod-level, not regional"
    echo "   Check quota at: https://console.cloud.google.com/iam-admin/quotas"
    echo "   Look for: 'TPU v6e' or 'TPU v5e' quotas in region $REGION"
else
    echo -e "${YELLOW}⚠️  No accelerator specified for quota check${NC}"
    echo "   Checking CPU quota only..."

    # Check CPU quota as fallback
    CPU_QUOTA=$(gcloud compute regions describe $REGION --project=$PROJECT_ID 2>&1 | \
        grep -B1 -A1 "metric: CPUS$" | grep -E "limit:|usage:")

    if [[ -n "$CPU_QUOTA" ]]; then
        CPU_LIMIT=$(echo "$CPU_QUOTA" | grep "limit:" | awk '{print $2}' | cut -d'.' -f1)
        CPU_USAGE=$(echo "$CPU_QUOTA" | grep "usage:" | awk '{print $2}' | cut -d'.' -f1)
        CPU_AVAIL=$((CPU_LIMIT - CPU_USAGE))

        echo "   CPUs: Limit=$CPU_LIMIT | Usage=$CPU_USAGE | Available=$CPU_AVAIL"
    fi
fi
echo ""

# ============================================================================
# Check 5b: Capacity/Stockout Detection
# ============================================================================
echo "========================================="
echo "Check 5b: Capacity Indicators"
echo "========================================="
echo "Note: True stockouts can only be detected by attempting creation."
echo "      These indicators help assess likelihood of available capacity:"
echo ""

# Check for existing successful deployments
if [ "$IS_TPU" = true ]; then
    EXISTING=$(gcloud compute instances list \
        --filter="zone:($ZONE) AND machineType:$MACHINE_TYPE" \
        --format="value(name)" \
        --project=$PROJECT_ID 2>/dev/null | wc -l)

    if [ "$EXISTING" -gt 0 ]; then
        echo -e "${GREEN}✅ Found $EXISTING existing instance(s) with $MACHINE_TYPE in $ZONE${NC}"
        echo "   This indicates capacity was recently available"
    else
        echo -e "${YELLOW}⚠️  No existing instances found with $MACHINE_TYPE in $ZONE${NC}"
        echo "   This may indicate limited capacity or new machine type"
    fi

elif [ "$IS_GPU" = true ] && [[ -n "$ACCELERATOR" ]]; then
    # For GPUs, check for instances with accelerators
    # Note: This is harder to detect as accelerators are attached separately
    EXISTING=$(gcloud compute instances list \
        --filter="zone:($ZONE)" \
        --format="value(name)" \
        --project=$PROJECT_ID 2>/dev/null | wc -l)

    if [ "$EXISTING" -gt 0 ]; then
        echo -e "${GREEN}✅ Found $EXISTING instance(s) in $ZONE${NC}"
        echo "   Zone appears to have active compute capacity"
    else
        echo -e "${YELLOW}⚠️  No existing instances found in $ZONE${NC}"
    fi

    # Check for GKE node pools with GPUs in the region
    REGION=$(echo $ZONE | sed 's/-[^-]*$//')
    GPU_POOLS=$(gcloud compute instances list \
        --filter="zone:($ZONE) AND name:gke-*" \
        --format="value(name)" \
        --project=$PROJECT_ID 2>/dev/null | wc -l)

    if [ "$GPU_POOLS" -gt 0 ]; then
        echo -e "${GREEN}✅ Found $GPU_POOLS GKE node(s) in $ZONE${NC}"
        echo "   This suggests GKE capacity is available"
    fi
fi

# Check zone status
ZONE_STATUS=$(gcloud compute zones describe $ZONE --format="value(status)" --project=$PROJECT_ID 2>/dev/null)
if [[ "$ZONE_STATUS" == "UP" ]]; then
    echo -e "${GREEN}✅ Zone status: UP (operational)${NC}"
elif [[ "$ZONE_STATUS" == "DOWN" ]]; then
    echo -e "${RED}❌ Zone status: DOWN (maintenance or outage)${NC}"
    ALL_CHECKS_PASSED=false
else
    echo -e "${YELLOW}⚠️  Zone status: $ZONE_STATUS${NC}"
fi

echo ""
echo "Capacity Recommendations:"
echo "  • TPU stockouts are rare but can occur during high demand"
echo "  • GPU stockouts (especially H100, A100) are more common"
echo "  • Consider multiple zones for critical deployments"
echo "  • Use autoscaling with min-nodes=0 to handle temporary stockouts"
echo ""

# ============================================================================
# Check 6: Cluster Compatibility (if cluster specified)
# ============================================================================
if [[ -n "$CLUSTER" ]]; then
    echo "========================================="
    echo "Check 6: Cluster Compatibility"
    echo "========================================="

    CLUSTER_INFO=$(gcloud container clusters describe $CLUSTER --zone=$ZONE --project=$PROJECT_ID 2>&1)
    if echo "$CLUSTER_INFO" | grep -q "name: $CLUSTER"; then
        echo -e "${GREEN}✅ Cluster $CLUSTER exists in $ZONE${NC}"

        # Check cluster location
        CLUSTER_ZONE=$(echo "$CLUSTER_INFO" | grep "^zone:" | awk '{print $2}')
        if [[ "$CLUSTER_ZONE" == "$ZONE" ]]; then
            echo -e "${GREEN}✅ Cluster zone matches node pool zone${NC}"
        else
            echo -e "${RED}❌ Cluster is in $CLUSTER_ZONE, but node pool zone is $ZONE${NC}"
            ALL_CHECKS_PASSED=false
        fi

        # Check cluster status
        CLUSTER_STATUS=$(echo "$CLUSTER_INFO" | grep "^status:" | awk '{print $2}')
        if [[ "$CLUSTER_STATUS" == "RUNNING" ]]; then
            echo -e "${GREEN}✅ Cluster is RUNNING${NC}"
        else
            echo -e "${YELLOW}⚠️  Cluster status: $CLUSTER_STATUS${NC}"
        fi

    else
        echo -e "${RED}❌ Cluster $CLUSTER not found in $ZONE${NC}"
        echo "   Error: $CLUSTER_INFO"
        ALL_CHECKS_PASSED=false
    fi
    echo ""
fi

# ============================================================================
# Check 7: Actual Capacity Test (if requested)
# ============================================================================
if [ "$TEST_CAPACITY" = true ]; then
    echo "========================================="
    echo "Check 7: Actual Capacity Test"
    echo "========================================="
    echo -e "${YELLOW}⚠️  WARNING: This test will attempt to create a test instance!${NC}"
    echo "   The instance will be immediately deleted, but brief charges may apply."
    echo ""
    echo -e "${YELLOW}⚠️  IMPORTANT: For TPUs, this tests standalone TPU VM capacity.${NC}"
    echo "   GKE node pool capacity is separate and cannot be pre-tested."
    echo "   Only actual node pool creation during cluster setup will confirm"
    echo "   GKE TPU node pool availability."
    echo ""

    TEST_INSTANCE_NAME="capacity-test-$(date +%s)"

    if [ "$IS_TPU" = true ]; then
        echo -e "${YELLOW}Note: TPU capacity test creates a standalone TPU VM (not GKE node pool)${NC}"
        echo "      GKE node pool capacity is separate and can only be verified by"
        echo "      attempting actual node pool creation during cluster setup."
        echo ""
        echo "Testing standalone TPU VM capacity..."
        echo "   Instance name: $TEST_INSTANCE_NAME"
        echo "   This will take 30-60 seconds..."
        echo ""

        # Convert machine type to accelerator type (e.g., ct6e-standard-4t -> v6e-4)
        ACCELERATOR_TYPE=$(echo $MACHINE_TYPE | sed 's/ct/v/;s/-standard-/-/;s/t$//')

        # Attempt to create a small TPU VM instance
        CREATE_OUTPUT=$(gcloud compute tpus tpu-vm create $TEST_INSTANCE_NAME \
            --zone=$ZONE \
            --accelerator-type=$ACCELERATOR_TYPE \
            --version=tpu-vm-base \
            --project=$PROJECT_ID 2>&1)

        if echo "$CREATE_OUTPUT" | grep -q "Created"; then
            echo -e "${GREEN}✅ CAPACITY AVAILABLE: Successfully created test TPU VM instance${NC}"
            echo "   (Note: GKE node pool capacity may still differ)"
            echo "   Deleting test instance..."
            gcloud compute tpus tpu-vm delete $TEST_INSTANCE_NAME \
                --zone=$ZONE \
                --project=$PROJECT_ID \
                --quiet 2>&1 > /dev/null
            echo -e "${GREEN}✅ Test instance deleted${NC}"
        else
            if echo "$CREATE_OUTPUT" | grep -qi "quota\|QUOTA"; then
                echo -e "${RED}❌ QUOTA EXCEEDED: Insufficient quota${NC}"
                ALL_CHECKS_PASSED=false
            elif echo "$CREATE_OUTPUT" | grep -qi "stockout\|capacity\|ZONE_RESOURCE_POOL_EXHAUSTED\|RESOURCE_EXHAUSTED"; then
                echo -e "${RED}❌ STOCKOUT DETECTED: No standalone TPU VM capacity available in $ZONE${NC}"
                echo "   GKE node pool capacity may also be affected"
                echo "   Try alternative zones or wait for capacity to become available"
                ALL_CHECKS_PASSED=false
            elif echo "$CREATE_OUTPUT" | grep -qi "permission"; then
                echo -e "${YELLOW}⚠️  PERMISSION DENIED: Cannot create standalone TPU VMs${NC}"
                echo "   Your project may only have access to GKE TPU node pools"
                echo "   This is common and doesn't affect GKE deployment"
                echo "   Skipping capacity test..."
            else
                echo -e "${RED}❌ CAPACITY TEST FAILED${NC}"
                echo "   Error: $CREATE_OUTPUT"
                ALL_CHECKS_PASSED=false
            fi
        fi

    elif [ "$IS_GPU" = true ]; then
        echo "Testing GPU capacity by attempting instance creation..."
        echo "   Instance name: $TEST_INSTANCE_NAME"
        echo "   This will take 10-20 seconds..."
        echo ""

        # Build accelerator flag if specified
        ACCEL_FLAG=""
        if [[ -n "$ACCELERATOR" ]]; then
            ACCEL_FLAG="--accelerator=type=$ACCELERATOR,count=1"
        fi

        # Attempt to create a small GPU instance
        CREATE_OUTPUT=$(gcloud compute instances create $TEST_INSTANCE_NAME \
            --zone=$ZONE \
            --machine-type=$MACHINE_TYPE \
            $ACCEL_FLAG \
            --boot-disk-size=10GB \
            --project=$PROJECT_ID 2>&1)

        if echo "$CREATE_OUTPUT" | grep -q "Created"; then
            echo -e "${GREEN}✅ CAPACITY AVAILABLE: Successfully created test GPU instance${NC}"
            echo "   Deleting test instance..."
            gcloud compute instances delete $TEST_INSTANCE_NAME \
                --zone=$ZONE \
                --project=$PROJECT_ID \
                --quiet 2>&1 > /dev/null
            echo -e "${GREEN}✅ Test instance deleted${NC}"
        else
            if echo "$CREATE_OUTPUT" | grep -qi "quota\|QUOTA"; then
                echo -e "${RED}❌ QUOTA EXCEEDED: Insufficient quota${NC}"
                ALL_CHECKS_PASSED=false
            elif echo "$CREATE_OUTPUT" | grep -qi "stockout\|capacity\|ZONE_RESOURCE_POOL_EXHAUSTED"; then
                echo -e "${RED}❌ STOCKOUT DETECTED: No capacity available in $ZONE${NC}"
                echo "   Try alternative zones or wait for capacity to become available"
                ALL_CHECKS_PASSED=false
            else
                echo -e "${RED}❌ CAPACITY TEST FAILED${NC}"
                echo "   Error: $CREATE_OUTPUT"
                ALL_CHECKS_PASSED=false
            fi
        fi
    fi

    echo ""
fi

# ============================================================================
# Final Summary
# ============================================================================
echo "========================================="
echo "Summary"
echo "========================================="

if [ "$ALL_CHECKS_PASSED" = true ]; then
    echo -e "${GREEN}✅ All checks PASSED!${NC}"
    echo ""
    echo "You can proceed with node pool creation:"
    echo ""

    if [ "$IS_TPU" = true ]; then
        echo "gcloud container node-pools create my-nodepool \\"
        [[ -n "$CLUSTER" ]] && echo "  --cluster=$CLUSTER \\" || echo "  --cluster=YOUR_CLUSTER \\"
        echo "  --zone=$ZONE \\"
        echo "  --machine-type=$MACHINE_TYPE \\"
        [[ -n "$TPU_TOPOLOGY" ]] && echo "  --tpu-topology=$TPU_TOPOLOGY \\"
        echo "  --num-nodes=1"
    else
        echo "gcloud container node-pools create my-nodepool \\"
        [[ -n "$CLUSTER" ]] && echo "  --cluster=$CLUSTER \\" || echo "  --cluster=YOUR_CLUSTER \\"
        echo "  --zone=$ZONE \\"
        echo "  --machine-type=$MACHINE_TYPE \\"
        [[ -n "$ACCELERATOR" ]] && echo "  --accelerator type=$ACCELERATOR,count=1 \\"
        echo "  --num-nodes=1"
    fi
else
    echo -e "${RED}❌ Some checks FAILED!${NC}"
    echo ""
    echo "Please resolve the issues above before creating the node pool."

    if [ "$CUSTOMER_MODE" = true ]; then
        echo ""
        echo "========================================="
        echo "💡 COMMON SOLUTIONS"
        echo "========================================="
        echo ""

        if [ "$IS_TPU" = true ]; then
            echo "If quota check failed:"
            echo "  1. Request quota increase in GCP Console:"
            echo "     https://console.cloud.google.com/iam-admin/quotas"
            echo "  2. Search for: 'TPU v6e' in region: ${ZONE%-*}"
            echo "  3. Request: 12 chips minimum (for 3-node scale-out)"
            echo "  4. Justification: 'LLM inference deployment for production workloads'"
            echo "  5. Approval time: Usually 24-48 hours"
        else
            echo "If quota check failed:"
            echo "  1. Request quota increase in GCP Console:"
            echo "     https://console.cloud.google.com/iam-admin/quotas"
            echo "  2. Search for: '$ACCELERATOR' in region: ${ZONE%-*}"
            echo "  3. Request: 3 GPUs minimum (for scale-out deployment)"
            echo "  4. Justification: 'LLM inference deployment for development/testing'"
            echo "  5. Approval time: Usually instant for T4, 24-48h for A100/H100"
        fi

        echo ""
        echo "If accelerator not available in zone:"
        echo "  Try running: ./scripts/check-accelerator-availability.sh --customer"
        echo "  This will show alternative zones with availability."
        echo ""
        echo "========================================="
    fi

    exit 1
fi

# Customer-friendly summary
if [ "$CUSTOMER_MODE" = true ] && [ "$ALL_CHECKS_PASSED" = true ]; then
    echo ""
    echo "========================================="
    echo "✅ READY FOR CLUSTER CREATION"
    echo "========================================="
    echo ""
    echo "⏱️  Estimated cluster creation time:"

    if [ "$IS_TPU" = true ]; then
        echo "   • Cluster creation: ~5 minutes"
        echo "   • TPU node pool: ~10-15 minutes"
        echo "   • Total: ~20 minutes"
    else
        echo "   • Cluster creation: ~5 minutes"
        echo "   • GPU node pool: ~5-10 minutes"
        echo "   • Total: ~15 minutes"
    fi

    echo ""
    echo "📚 Next step:"
    if [ "$IS_TPU" = true ]; then
        echo "   ./scripts/create-gke-cluster.sh --tpu --zone $ZONE"
    else
        echo "   ./scripts/create-gke-cluster.sh --gpu --zone $ZONE"
    fi
    echo ""
fi

echo ""
echo "========================================="
