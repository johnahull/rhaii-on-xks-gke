#!/bin/bash
# Post-deployment verification for RHAII LLM deployments
# Validates operators, deployments, and inference endpoints

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Gateway configuration (matches setup-gateway.sh defaults)
GATEWAY_NAMESPACE="${GATEWAY_NAMESPACE:-opendatahub}"
GATEWAY_NAME="${GATEWAY_NAME:-inference-gateway}"

# Validation flags
ALL_CHECKS_PASSED=true

show_usage() {
    cat <<EOF
========================================
RHAII Deployment Verification
========================================

Verifies RHAII deployments are functioning correctly.

Usage: $0 [OPTIONS]

Options:
  --operators-only        Check operators only (cert-manager, Istio, KServe)
  --namespace <ns>        Kubernetes namespace (default: rhaii-inference)
  --timeout <seconds>     Timeout for checks (default: 300)
  --help, -h              Show this help message

Environment Variables:
  GATEWAY_NAMESPACE    Gateway namespace (default: opendatahub)
  GATEWAY_NAME         Gateway name (default: inference-gateway)

Examples:
  # Verify operators are running
  $0 --operators-only

  # Verify deployment
  $0

  # Verify in specific namespace
  $0 --namespace llm-serving

========================================
EOF
}

# Parse arguments
OPERATORS_ONLY=false
NAMESPACE="rhaii-inference"
TIMEOUT=300

while [[ $# -gt 0 ]]; do
    case $1 in
        --operators-only)
            OPERATORS_ONLY=true
            shift
            ;;
        --namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        --timeout)
            TIMEOUT="$2"
            shift 2
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
# Helper Functions
# ============================================================================

check_pod_status() {
    local namespace=$1
    local label=$2
    local name=$3

    echo -n "  Checking $name pods... "

    # Check if pods exist
    POD_COUNT=$(kubectl get pods -n "$namespace" -l "$label" --no-headers 2>/dev/null | wc -l)
    if [[ "$POD_COUNT" -eq 0 ]]; then
        echo -e "${RED}NOT FOUND${NC}"
        ALL_CHECKS_PASSED=false
        return 1
    fi

    # Check if pods are running
    RUNNING_COUNT=$(kubectl get pods -n "$namespace" -l "$label" --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
    if [[ "$RUNNING_COUNT" -eq "$POD_COUNT" ]]; then
        echo -e "${GREEN}✅ $RUNNING_COUNT/$POD_COUNT running${NC}"
        return 0
    else
        echo -e "${RED}❌ $RUNNING_COUNT/$POD_COUNT running${NC}"
        ALL_CHECKS_PASSED=false
        kubectl get pods -n "$namespace" -l "$label" | grep -v Running || true
        return 1
    fi
}

test_http_endpoint() {
    local url=$1
    local expected_code=$2
    local description=$3

    echo -n "  Testing $description... "

    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || echo "000")
    if [[ "$HTTP_CODE" == "$expected_code" ]]; then
        echo -e "${GREEN}✅ $HTTP_CODE${NC}"
        return 0
    else
        echo -e "${RED}❌ $HTTP_CODE (expected $expected_code)${NC}"
        ALL_CHECKS_PASSED=false
        return 1
    fi
}

# ============================================================================
# Operator Verification
# ============================================================================

echo "========================================="
echo "Operator Verification"
echo "========================================="
echo ""

# cert-manager
echo "cert-manager:"
check_pod_status "cert-manager" "app.kubernetes.io/instance=cert-manager" "cert-manager"
echo ""

# Istio
echo "Istio (Service Mesh):"
check_pod_status "istio-system" "app=istiod" "istiod"
check_pod_status "$GATEWAY_NAMESPACE" "gateway.networking.k8s.io/gateway-name=$GATEWAY_NAME" "inference-gateway"
echo ""

# KServe
echo "KServe:"
check_pod_status "$GATEWAY_NAMESPACE" "control-plane=kserve-controller-manager" "kserve-controller"
echo ""

# LWS (LeaderWorkerSet)
echo "LWS (LeaderWorkerSet):"
check_pod_status "openshift-lws-operator" "name=openshift-lws-operator" "lws-controller"
echo ""

if [[ "$OPERATORS_ONLY" == "true" ]]; then
    echo "========================================="
    if [[ "$ALL_CHECKS_PASSED" == "true" ]]; then
        echo -e "${GREEN}✅ All operator checks PASSED${NC}"
        echo ""
        echo "Next step: Deploy your workload"
        echo "  docs/deployment-tpu.md"
        echo "  docs/deployment-gpu.md"
    else
        echo -e "${RED}❌ Some operator checks FAILED${NC}"
        echo ""
        echo "Troubleshooting:"
        echo "  1. Check operator installation:"
        echo "     kubectl get pods -A"
        echo "  2. Review operator logs:"
        echo "     kubectl logs -n <namespace> <pod-name>"
        echo "  3. See: docs/troubleshooting.md"
    fi
    echo "========================================="
    exit $([ "$ALL_CHECKS_PASSED" == "true" ] && echo 0 || echo 1)
fi

# ============================================================================
# Deployment Verification
# ============================================================================

echo "========================================="
echo "Deployment Verification"
echo "========================================="
echo ""

# Check for LLMInferenceService
echo "LLMInferenceService:"
LLMISVC_COUNT=$(kubectl get llminferenceservice -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)
if [[ "$LLMISVC_COUNT" -eq 0 ]]; then
    echo -e "${RED}❌ No LLMInferenceService found in namespace: $NAMESPACE${NC}"
    ALL_CHECKS_PASSED=false
else
    echo "  Found $LLMISVC_COUNT LLMInferenceService(s)"
    kubectl get llminferenceservice -n "$NAMESPACE"

    # Check READY status
    READY_COUNT=$(kubectl get llminferenceservice -n "$NAMESPACE" -o json | jq '[.items[] | select(.status.conditions[]? | select(.type=="Ready" and .status=="True"))] | length' 2>/dev/null || echo 0)
    if [[ "$READY_COUNT" -eq "$LLMISVC_COUNT" ]]; then
        echo -e "${GREEN}✅ All LLMInferenceServices are READY${NC}"
    else
        echo -e "${RED}❌ $READY_COUNT/$LLMISVC_COUNT LLMInferenceServices are READY${NC}"
        ALL_CHECKS_PASSED=false
    fi
fi
echo ""

# Check Gateway
echo "Inference Gateway:"
GATEWAY_IP=$(kubectl get gateway "$GATEWAY_NAME" -n "$GATEWAY_NAMESPACE" -o jsonpath='{.status.addresses[0].value}' 2>/dev/null || echo "")
if [[ -z "$GATEWAY_IP" ]]; then
    echo -e "${RED}❌ No external IP assigned to Gateway${NC}"
    ALL_CHECKS_PASSED=false
else
    echo -e "${GREEN}✅ Gateway IP: $GATEWAY_IP${NC}"

    # Test health endpoint
    echo ""
    echo "Health Endpoint:"
    # Find the first LLMInferenceService name
    LLMISVC_NAME=$(kubectl get llminferenceservice -n "$NAMESPACE" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    if [[ -n "$LLMISVC_NAME" ]]; then
        HEALTH_URL="http://$GATEWAY_IP/v1/health"
        test_http_endpoint "$HEALTH_URL" "200" "health endpoint"

        # Test inference endpoint
        echo ""
        echo "Inference Endpoint:"
        INFERENCE_URL="http://$GATEWAY_IP/v1/models"
        test_http_endpoint "$INFERENCE_URL" "200" "models endpoint"

        # Perform actual inference test
        echo ""
        echo "Test Inference Request:"
        echo -n "  Sending completion request... "
        INFERENCE_RESPONSE=$(curl -s -X POST "http://$GATEWAY_IP/v1/completions" \
            -H "Content-Type: application/json" \
            -d '{"model": "google/gemma-2b-it", "prompt": "Hello", "max_tokens": 10}' \
            2>/dev/null || echo "")

        if echo "$INFERENCE_RESPONSE" | grep -q "choices"; then
            echo -e "${GREEN}✅ Inference successful${NC}"
            echo "     Response: $(echo "$INFERENCE_RESPONSE" | jq -r '.choices[0].text' 2>/dev/null | head -c 50)..."
        else
            echo -e "${RED}❌ Inference failed${NC}"
            echo "     Response: $INFERENCE_RESPONSE"
            ALL_CHECKS_PASSED=false
        fi
    fi
fi
echo ""

# Scale-out checks
echo "Scale-Out Checks:"

# Check replica count
REPLICA_COUNT=$(kubectl get pods -n "$NAMESPACE" -l serving.kserve.io/inferenceservice --no-headers 2>/dev/null | wc -l)
if [[ "$REPLICA_COUNT" -eq 3 ]]; then
    echo -e "${GREEN}✅ 3 replicas running${NC}"
else
    echo -e "${YELLOW}⚠️  $REPLICA_COUNT replicas (expected 3)${NC}"
fi

# Check NetworkPolicies
NP_COUNT=$(kubectl get networkpolicies -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l)
if [[ "$NP_COUNT" -gt 0 ]]; then
    echo -e "${GREEN}✅ NetworkPolicies configured ($NP_COUNT)${NC}"
else
    echo -e "${YELLOW}⚠️  No NetworkPolicies found${NC}"
fi

echo ""

# ============================================================================
# Final Summary
# ============================================================================

echo "========================================="
echo "Verification Summary"
echo "========================================="
echo ""

if [[ "$ALL_CHECKS_PASSED" == "true" ]]; then
    echo -e "${GREEN}✅ ALL CHECKS PASSED!${NC}"
    echo ""
    echo "Your deployment is ready for use."
    echo ""
    if [[ -n "$GATEWAY_IP" ]]; then
        echo "Inference endpoint: http://$GATEWAY_IP/v1/completions"
        echo ""
        echo "Test with:"
        echo "curl -X POST http://$GATEWAY_IP/v1/completions \\"
        echo "  -H 'Content-Type: application/json' \\"
        echo "  -d '{\"model\": \"google/gemma-2b-it\", \"prompt\": \"Hello\", \"max_tokens\": 50}'"
    fi
    echo ""
    echo "Next steps:"
    echo "  • Troubleshooting: docs/troubleshooting.md"
else
    echo -e "${RED}❌ SOME CHECKS FAILED${NC}"
    echo ""
    echo "Troubleshooting steps:"
    echo "  1. Review failed checks above"
    echo "  2. Check pod logs: kubectl logs -n <namespace> <pod-name>"
    echo "  3. See: docs/troubleshooting.md"
    exit 1
fi

echo ""
echo "========================================="
