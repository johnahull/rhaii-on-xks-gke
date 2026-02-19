# How gateway-api-inference-extension Gets on the Cluster

## The Short Answer

`gateway-api-inference-extension` is **not an operator** - it's a Go library that gets compiled into the EPP scheduler container image. That image is then deployed by the **KServe controller** when you create a LLMInferenceService.

## Complete Deployment Flow

```
┌─────────────────────────────────────────────────────────────────┐
│ Step 1: Build Time (Off-Cluster)                                │
└─────────────────────────────────────────────────────────────────┘

Source Repository: gateway-api-inference-extension
├── pkg/epp/server/runserver.go    (EPP scheduler implementation)
├── pkg/bbr/server/runserver.go    (BBR scheduler implementation)
└── cmd/epp/runner/                (EPP entrypoint)
                │
                │ (Go module dependency)
                ▼
Source Repository: llm-d-inference-scheduler
├── go.mod
│   └── require sigs.k8s.io/gateway-api-inference-extension v0.5.0
├── Dockerfile.epp                 (Build instructions)
└── [Compiled binary includes gateway-api-inference-extension code]
                │
                │ (Docker/Podman build)
                ▼
Container Image: gcr.io/ecoeng-llmd/llm-d-inference-scheduler:latest
├── Binary: /usr/local/bin/epp-scheduler
│   └── Contains compiled gateway-api-inference-extension code
├── Libraries: ZeroMQ, CA certs
└── Runtime: UBI9

                │
                │ (Push to registry)
                ▼
Container Registry: gcr.io/ecoeng-llmd/


┌─────────────────────────────────────────────────────────────────┐
│ Step 2: Cluster Setup (Operators Only)                          │
└─────────────────────────────────────────────────────────────────┘

User runs: cd /home/jhull/devel/rhaii-on-xks && make deploy-all

Installs these operators:
1. cert-manager          (TLS certificate management)
2. Istio (sail-operator) (Service mesh)
3. KServe v0.15          (Inference workload controller) ⭐
4. LeaderWorkerSet       (Multi-pod workload controller)

                │
                │ (Operators are now watching for CRDs)
                ▼
KServe Controller is running and waiting for LLMInferenceService resources


┌─────────────────────────────────────────────────────────────────┐
│ Step 3: Deploy Workload (User Creates LLMInferenceService)      │
└─────────────────────────────────────────────────────────────────┘

User runs: kubectl apply -f llmisvc-gpu-alpn-test-phi3.yaml

apiVersion: serving.kserve.io/v1alpha1
kind: LLMInferenceService
metadata:
  name: phi3-gpu-alpn-test
  namespace: rhaii-inference
spec:
  replicas: 3
  router:
    route: {}
    gateway: {}
    scheduler: {}  # ⬅️ This triggers EPP scheduler deployment!

                │
                │ (KServe controller reconciles)
                ▼

KServe Controller Logic:
1. Sees spec.router.scheduler: {}
2. Creates Deployment for EPP scheduler:
   - Name: phi3-gpu-alpn-test-kserve-router-scheduler
   - Image: gcr.io/ecoeng-llmd/llm-d-inference-scheduler:latest
   - Container name: main
   - Command: /usr/local/bin/epp-scheduler
   - Args: --grpc-port=9002, --grpc-health-port=9003, --secure-serving

3. Creates Service for EPP scheduler:
   - Name: phi3-gpu-alpn-test-epp-service
   - Ports: 9002 (gRPC), 9003 (health), 9090 (metrics)

4. Mounts TLS certificates from KServe cert-manager

                │
                │ (Pod scheduled)
                ▼

┌─────────────────────────────────────────────────────────────────┐
│ Step 4: Runtime (EPP Scheduler Running on Cluster)              │
└─────────────────────────────────────────────────────────────────┘

Pod: phi3-gpu-alpn-test-kserve-router-scheduler-xxxxx
└── Container: main
    ├── Image: gcr.io/ecoeng-llmd/llm-d-inference-scheduler:latest
    ├── Process: /usr/local/bin/epp-scheduler
    │   └── Contains gateway-api-inference-extension code ⭐
    ├── gRPC Server: 0.0.0.0:9002 (with TLS + ALPN h2)
    ├── Health Server: 0.0.0.0:9003
    └── Metrics Server: 0.0.0.0:9090

                │
                │ (Receives requests from Envoy)
                ▼

Envoy Gateway → ext_proc filter → gRPC/TLS (ALPN h2) → EPP Scheduler
                                                          (running compiled
                                                           gateway-api-inference-extension
                                                           code)
```

## Key Points

**1. gateway-api-inference-extension is NOT an operator**
   - It's a Go library (like `net/http` or `google.golang.org/grpc`)
   - Provides EPP and BBR scheduler implementations
   - Gets compiled into other programs

**2. llm-d-inference-scheduler is NOT an operator**
   - It's an application binary
   - Imports gateway-api-inference-extension as a dependency
   - Gets packaged into a container image

**3. KServe IS an operator**
   - Watches for LLMInferenceService resources
   - Automatically deploys EPP scheduler when `spec.router.scheduler: {}` is present
   - Manages the lifecycle of the scheduler pod

## How the ALPN Fix Gets Deployed

### Current State (With Fix)

```bash
# 1. Build custom image with ALPN fix
cd /home/jhull/devel/llm-d-inference-scheduler
podman build -f Dockerfile.epp -t gcr.io/ecoeng-llmd/llm-d-inference-scheduler:alpn-fix .
podman push gcr.io/ecoeng-llmd/llm-d-inference-scheduler:alpn-fix

# 2. Reference custom image in LLMInferenceService
kubectl apply -f - <<EOF
apiVersion: serving.kserve.io/v1alpha1
kind: LLMInferenceService
metadata:
  name: phi3-gpu-alpn-test
spec:
  router:
    scheduler:
      image: gcr.io/ecoeng-llmd/llm-d-inference-scheduler:alpn-fix  # Custom image
EOF

# 3. KServe controller deploys pod with our custom image
```

### After Upstream Merge (Normal Flow)

```bash
# 1. Fix is merged into gateway-api-inference-extension upstream
# 2. llm-d-inference-scheduler updates its go.mod dependency
# 3. llm-d-inference-scheduler builds new release images
# 4. Users deploy LLMInferenceService (no custom image needed)

kubectl apply -f - <<EOF
apiVersion: serving.kserve.io/v1alpha1
kind: LLMInferenceService
metadata:
  name: phi3-gpu-alpn-test
spec:
  router:
    scheduler: {}  # Uses default image (which now has the fix)
EOF
```

## Verification

You can see this in action on your cluster:

```bash
# 1. Check the LLMInferenceService
kubectl get llminferenceservice phi3-gpu-alpn-test -n rhaii-inference -o yaml

# 2. See the scheduler deployment created by KServe
kubectl get deployment -n rhaii-inference -l app.kubernetes.io/component=router-scheduler

# 3. Check the pod running the compiled gateway-api-inference-extension code
kubectl get pods -n rhaii-inference -l app.kubernetes.io/component=router-scheduler

# 4. Inspect the container image being used
kubectl get deployment phi3-gpu-alpn-test-kserve-router-scheduler -n rhaii-inference -o jsonpath='{.spec.template.spec.containers[0].image}'
# Output: gcr.io/ecoeng-llmd/llm-d-inference-scheduler:alpn-fix
```

## Summary

| Component | Type | How It Gets on Cluster |
|-----------|------|------------------------|
| gateway-api-inference-extension | Go Library | Compiled into llm-d-inference-scheduler binary |
| llm-d-inference-scheduler | Application | Packaged as container image |
| Container Image | OCI Image | Pushed to gcr.io registry |
| KServe Controller | Operator | Installed via `make deploy-all` |
| EPP Scheduler Pod | Workload | Deployed by KServe when LLMInferenceService created |

**The fix flows through this chain:**
1. Fix code in gateway-api-inference-extension
2. Build llm-d-inference-scheduler with updated dependency
3. Push new container image
4. KServe deploys that image when LLMInferenceService is created
