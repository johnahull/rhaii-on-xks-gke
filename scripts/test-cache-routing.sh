#!/bin/bash
# Test cache-aware routing and performance for RHAII deployments
# Validates health endpoints, cache hit behavior, and throughput

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Defaults
MODEL="/mnt/models"  # vLLM serves model mounted at /mnt/models (auto-detected)
NUM_REQUESTS=10
CONCURRENT=5
PROMPT="Translate to French: Hello world"
MAX_TOKENS=10
GATEWAY_IP=""

show_usage() {
    cat <<EOF
========================================
RHAII Cache Routing Test
========================================

Tests cache-aware routing, health endpoints, and throughput.

Usage: $0 [OPTIONS]

Options:
  --model <model>           Model name (default: /mnt/models, auto-detected)
  --prompt <prompt>         Prompt for cache test (default: "Translate to French: Hello world")
  --requests <n>            Number of sequential cache test requests (default: 10)
  --concurrent <n>          Number of parallel throughput requests (default: 5)
  --max-tokens <n>          Max tokens per response (default: 10)
  --endpoint <ip>           Gateway IP (default: auto-detect from kubectl)
  --help, -h                Show this help message

Examples:
  # Run with auto-detected gateway
  $0

  # Custom prompt and request count
  $0 --prompt "Summarize: The quick brown fox" --requests 20

  # Specify endpoint directly
  $0 --endpoint 34.6.79.145

========================================
EOF
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --model)
            MODEL="$2"
            shift 2
            ;;
        --prompt)
            PROMPT="$2"
            shift 2
            ;;
        --requests)
            NUM_REQUESTS="$2"
            shift 2
            ;;
        --concurrent)
            CONCURRENT="$2"
            shift 2
            ;;
        --max-tokens)
            MAX_TOKENS="$2"
            shift 2
            ;;
        --endpoint)
            GATEWAY_IP="$2"
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

# Auto-detect Gateway IP if not provided
if [[ -z "$GATEWAY_IP" ]]; then
    echo -n "Detecting Gateway IP... "
    GATEWAY_IP=$(kubectl get gateway "${GATEWAY_NAME:-inference-gateway}" -n "${GATEWAY_NAMESPACE:-opendatahub}" -o jsonpath='{.status.addresses[0].value}' 2>/dev/null || echo "")
    if [[ -z "$GATEWAY_IP" ]]; then
        echo -e "${RED}FAILED${NC}"
        echo ""
        echo "Could not detect Gateway IP. Either:"
        echo "  1. Ensure inference-gateway has an external IP:"
        echo "     kubectl get gateway inference-gateway -n opendatahub"
        echo "  2. Provide the IP directly:"
        echo "     $0 --endpoint <IP>"
        exit 1
    fi
    echo -e "${GREEN}$GATEWAY_IP${NC}"
fi

# Auto-detect LLMInferenceService name and build path prefix
NAMESPACE="${NAMESPACE:-rhaii-inference}"
LLMISVC_NAME=$(kubectl get llminferenceservice -n "$NAMESPACE" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [[ -z "$LLMISVC_NAME" ]]; then
    echo -e "${RED}No LLMInferenceService found in namespace: $NAMESPACE${NC}"
    exit 1
fi
BASE_URL="http://$GATEWAY_IP/$NAMESPACE/$LLMISVC_NAME"

# Auto-detect model name from vLLM if not overridden
if [[ "$MODEL" == "/mnt/models" ]]; then
    DETECTED_MODEL=$(curl -s "$BASE_URL/v1/models" 2>/dev/null | jq -r '.data[0].id' 2>/dev/null || echo "")
    if [[ -n "$DETECTED_MODEL" ]]; then
        MODEL="$DETECTED_MODEL"
    fi
fi

ALL_PASSED=true

echo ""
echo "========================================="
echo "RHAII Cache Routing Test"
echo "========================================="
echo ""
echo "Endpoint:    $BASE_URL"
echo "Model:       $MODEL"
echo "Prompt:      \"$PROMPT\""
echo "Requests:    $NUM_REQUESTS (sequential) + $CONCURRENT (parallel)"
echo ""

# ============================================================================
# Model Information
# ============================================================================
echo "========================================="
echo "1. Model Information"
echo "========================================="
echo ""

MODEL_INFO=$(curl -s "$BASE_URL/v1/models" 2>/dev/null)
if [[ $? -eq 0 ]] && [[ -n "$MODEL_INFO" ]]; then
    echo -e "${GREEN}✓${NC} /v1/models endpoint accessible"
    echo ""
    echo "Model response:"
    echo "$MODEL_INFO" | jq '.' 2>/dev/null || echo "$MODEL_INFO"
    echo ""
else
    echo -e "${RED}✗${NC} Failed to retrieve model information"
    ALL_PASSED=false
fi

echo ""

# ============================================================================
# Health Checks
# ============================================================================
echo "========================================="
echo "2. Health Checks"
echo "========================================="
echo ""

# Health endpoint
echo -n "  /health ... "
HEALTH_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/health" 2>/dev/null || echo "000")
if [[ "$HEALTH_CODE" == "200" ]]; then
    echo -e "${GREEN}OK (200)${NC}"
else
    echo -e "${RED}FAILED ($HEALTH_CODE)${NC}"
    ALL_PASSED=false
fi

# Models endpoint
echo -n "  /v1/models ... "
MODELS_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$BASE_URL/v1/models" 2>/dev/null || echo "000")
if [[ "$MODELS_CODE" == "200" ]]; then
    echo -e "${GREEN}OK (200)${NC}"
else
    echo -e "${RED}FAILED ($MODELS_CODE)${NC}"
    ALL_PASSED=false
fi

# Completions endpoint (single request)
echo -n "  /v1/completions ... "
COMPLETIONS_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$BASE_URL/v1/completions" \
    -H "Content-Type: application/json" \
    -d "{\"model\": \"$MODEL\", \"prompt\": \"Hello\", \"max_tokens\": 5}" 2>/dev/null || echo -e "\n000")
COMPLETIONS_CODE=$(echo "$COMPLETIONS_RESPONSE" | tail -1)
COMPLETIONS_BODY=$(echo "$COMPLETIONS_RESPONSE" | sed '$d')
if [[ "$COMPLETIONS_CODE" == "200" ]] && echo "$COMPLETIONS_BODY" | grep -q "choices"; then
    echo -e "${GREEN}OK (200)${NC}"
else
    echo -e "${RED}FAILED ($COMPLETIONS_CODE)${NC}"
    ALL_PASSED=false
fi

echo ""

# ============================================================================
# Cache Routing Test
# ============================================================================
echo "========================================="
echo "3. Cache Routing Test ($NUM_REQUESTS sequential requests)"
echo "========================================="
echo ""
echo "Testing with model: $MODEL"
echo "Prompt: \"$PROMPT\""
echo ""
echo "Sending $NUM_REQUESTS requests with identical prefix..."
echo "First request should be slower (cache miss), subsequent faster (cache hit)."
echo ""

TIMES=()
FIRST=""
for i in $(seq 1 "$NUM_REQUESTS"); do
    RESPONSE=$(curl -s -w "\n%{time_total}" -X POST "$BASE_URL/v1/completions" \
        -H "Content-Type: application/json" \
        -d "{\"model\": \"$MODEL\", \"prompt\": \"$PROMPT\", \"max_tokens\": $MAX_TOKENS}" 2>/dev/null)

    TIME_TOTAL=$(echo "$RESPONSE" | tail -1)
    TIME_MS=$(echo "$TIME_TOTAL" | awk '{printf "%.0f", $1 * 1000}')
    TIMES+=("$TIME_MS")

    # Label cache behavior explicitly
    if [[ $i -eq 1 ]]; then
        printf "  Request %2d: %6s ms  ${YELLOW}← CACHE MISS${NC} (first request, cold prefix)\n" "$i" "$TIME_MS"
        FIRST=$TIME_MS
    else
        # Check if this is faster than first (cache hit indicator)
        if [[ $TIME_MS -lt $FIRST ]]; then
            printf "  Request %2d: %6s ms  ${GREEN}← CACHE HIT${NC} (prefix cached)\n" "$i" "$TIME_MS"
        else
            printf "  Request %2d: %6s ms\n" "$i" "$TIME_MS"
        fi
    fi
done

# Calculate stats
FIRST=${TIMES[0]}
SUM=0
MIN=${TIMES[1]:-$FIRST}
MAX=${TIMES[1]:-$FIRST}
for t in "${TIMES[@]:1}"; do
    SUM=$((SUM + t))
    if [[ $t -lt $MIN ]]; then MIN=$t; fi
    if [[ $t -gt $MAX ]]; then MAX=$t; fi
done

if [[ ${#TIMES[@]} -gt 1 ]]; then
    SUBSEQUENT_COUNT=$(( ${#TIMES[@]} - 1 ))
    AVG=$((SUM / SUBSEQUENT_COUNT))

    echo ""
    echo "  Summary:"
    echo "    First request:      ${FIRST} ms"
    echo "    Subsequent avg:     ${AVG} ms (n=$SUBSEQUENT_COUNT)"
    echo "    Subsequent min/max: ${MIN}/${MAX} ms"

    # Check if cache routing is working (subsequent should be noticeably faster)
    if [[ $AVG -lt $FIRST ]]; then
        SPEEDUP=$(echo "$FIRST $AVG" | awk '{printf "%.0f", (1 - $2/$1) * 100}')
        echo -e "    Cache speedup:      ${GREEN}${SPEEDUP}% faster${NC}"
    else
        echo -e "    Cache speedup:      ${YELLOW}No improvement detected${NC}"
        echo "    (This may be normal if the model is still warming up)"
    fi
fi

echo ""

# ============================================================================
# Throughput Test
# ============================================================================
echo "========================================="
echo "4. Throughput Test ($CONCURRENT parallel requests)"
echo "========================================="
echo ""
echo "Firing $CONCURRENT requests in parallel..."
echo ""

TMPDIR=$(mktemp -d)
START_TIME=$(date +%s%N)

for i in $(seq 1 "$CONCURRENT"); do
    (
        RESP=$(curl -s -w "\n%{time_total}" -X POST "$BASE_URL/v1/completions" \
            -H "Content-Type: application/json" \
            -d "{\"model\": \"$MODEL\", \"prompt\": \"$PROMPT $i\", \"max_tokens\": $MAX_TOKENS}" 2>/dev/null)
        TIME=$(echo "$RESP" | tail -1)
        echo "$TIME" > "$TMPDIR/$i.time"
        CODE=$(echo "$RESP" | sed '$d' | grep -c "choices" 2>/dev/null || true)
        CODE=${CODE:-0}
        echo "$CODE" > "$TMPDIR/$i.ok"
    ) &
done
wait

END_TIME=$(date +%s%N)
WALL_MS=$(( (END_TIME - START_TIME) / 1000000 ))

SUCCEEDED=0
FAILED=0
TOTAL_TIME=0
P_TIMES=()
for i in $(seq 1 "$CONCURRENT"); do
    OK=$(cat "$TMPDIR/$i.ok" 2>/dev/null || echo "0")
    T=$(cat "$TMPDIR/$i.time" 2>/dev/null || echo "0")
    T_MS=$(echo "$T" | awk '{printf "%.0f", $1 * 1000}')
    P_TIMES+=("$T_MS")
    if [[ "$OK" -ge 1 ]]; then
        SUCCEEDED=$((SUCCEEDED + 1))
    else
        FAILED=$((FAILED + 1))
    fi
    TOTAL_TIME=$((TOTAL_TIME + T_MS))
done
rm -rf "$TMPDIR"

# Sort times for percentiles
IFS=$'\n' SORTED=($(sort -n <<<"${P_TIMES[*]}")); unset IFS

P50_IDX=$(( ${#SORTED[@]} / 2 ))
P99_IDX=$(( ${#SORTED[@]} - 1 ))

THROUGHPUT=$(echo "$CONCURRENT $WALL_MS" | awk '{printf "%.1f", $1 / ($2 / 1000)}')
AVG_LATENCY=$((TOTAL_TIME / CONCURRENT))

echo "  Results:"
echo "    Successful:   $SUCCEEDED / $CONCURRENT"
if [[ $FAILED -gt 0 ]]; then
    echo -e "    Failed:       ${RED}$FAILED${NC}"
    ALL_PASSED=false
fi
echo "    Wall time:    ${WALL_MS} ms"
echo "    Throughput:   ${THROUGHPUT} req/s"
echo "    Avg latency:  ${AVG_LATENCY} ms"
echo "    P50 latency:  ${SORTED[$P50_IDX]} ms"
echo "    P99 latency:  ${SORTED[$P99_IDX]} ms"
echo ""

# ============================================================================
# Summary
# ============================================================================
echo "========================================="
echo "Summary"
echo "========================================="
echo ""

if [[ "$ALL_PASSED" == "true" ]]; then
    echo -e "${GREEN}All checks passed.${NC}"
else
    echo -e "${RED}Some checks failed.${NC}"
    echo "Review the output above for details."
fi

echo ""
echo "Endpoint: $BASE_URL/v1/completions"
echo ""

# ============================================================================
# EPP Scheduler Weights Diagram
# ============================================================================
echo "========================================="
echo "EPP Scheduler Weights (Cache-Aware Routing)"
echo "========================================="
echo ""
echo "┌─────────────────────────────────────────────────────────┐"
echo "│  SCORER: prefix-cache-scorer                            │"
echo "│  WEIGHT: 1.0 (PRIMARY)                                  │"
echo "│                                                         │"
echo "│  Purpose: Route same prefix to same replica            │"
echo "│  Method: Hash prefix → score by cache affinity         │"
echo "└─────────────────────────────────────────────────────────┘"
echo ""
echo "┌─────────────────────────────────────────────────────────┐"
echo "│  SCORER: least-requests                                 │"
echo "│  WEIGHT: 0.5 (SECONDARY)                                │"
echo "│                                                         │"
echo "│  Purpose: Load balance across replicas                 │"
echo "│  Method: Score by inverse of active requests           │"
echo "└─────────────────────────────────────────────────────────┘"
echo ""
echo "Final Score = (cache × 1.0) + (load × 0.5)"
echo ""
echo "Verifying actual EPP scheduler state..."
echo ""

# Check InferencePool exists
INFERENCEPOOL_COUNT=$(kubectl get inferencepool -n "$NAMESPACE" 2>/dev/null | grep -v NAME | wc -l)
if [[ $INFERENCEPOOL_COUNT -gt 0 ]]; then
    echo -e "  ${GREEN}✓${NC} InferencePool resource exists"
    kubectl get inferencepool -n "$NAMESPACE" 2>/dev/null | head -2 | sed 's/^/    /'
else
    echo -e "  ${YELLOW}⚠${NC} No InferencePool found (may not be created yet)"
fi
echo ""

# Check EPP scheduler pod
EPP_POD=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/component=router-scheduler -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [[ -n "$EPP_POD" ]]; then
    EPP_STATUS=$(kubectl get pod "$EPP_POD" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null)
    if [[ "$EPP_STATUS" == "Running" ]]; then
        echo -e "  ${GREEN}✓${NC} EPP scheduler pod: $EPP_POD (Running)"
    else
        echo -e "  ${YELLOW}⚠${NC} EPP scheduler pod: $EPP_POD (Status: $EPP_STATUS)"
    fi

    # Try to get EPP metrics
    echo ""
    echo "  EPP Scheduler Metrics (scorer activity):"
    METRICS=$(kubectl exec -n "$NAMESPACE" "$EPP_POD" -- curl -s localhost:9090/metrics 2>/dev/null | grep -E "scorer|routing" | head -5)
    if [[ -n "$METRICS" ]]; then
        echo "$METRICS" | sed 's/^/    /'
    else
        echo "    (Metrics endpoint not accessible or no scorer metrics yet)"
    fi
else
    echo -e "  ${YELLOW}⚠${NC} EPP scheduler pod not found"
fi

echo ""
echo "To view real-time routing decisions:"
echo "  kubectl logs -n $NAMESPACE -l app.kubernetes.io/component=router-scheduler --tail=50 -f"
echo ""
echo "========================================="
