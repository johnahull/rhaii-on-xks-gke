# GCP Configuration
PROJECT_ID ?= $(shell gcloud config get-value project 2>/dev/null)
CLUSTER_NAME ?= rhaii-cluster
ZONE ?= europe-west4-a
ACCELERATOR ?= tpu

# Node Configuration
NUM_NODES ?= 3
CONTROL_NODE_COUNT ?= 2
CONTROL_MACHINE_TYPE ?= n1-standard-4

# TPU Configuration
TPU_MACHINE_TYPE ?= ct6e-standard-4t
TPU_NODEPOOL_NAME ?= tpu-pool

# GPU Configuration
GPU_MACHINE_TYPE ?= n1-standard-4
GPU_ACCELERATOR ?= nvidia-tesla-t4
GPU_NODEPOOL_NAME ?= gpu-pool
GPU_OPERATOR_VERSION ?= v25.10.0

# Namespace
WORKLOAD_NAMESPACE ?= rhaii-inference

.DEFAULT_GOAL := help

help:
	@echo "Usage:"
	@echo "   make <target> [VARIABLE=value ...]"
	@echo ""
	@echo "Common Workflows:"
	@echo "   make cluster-tpu                  -- Create full TPU cluster"
	@echo "   make cluster-gpu                  -- Create full GPU cluster with operator"
	@echo "   make check                        -- Validate prerequisites only"
	@echo ""
	@echo "Cluster Management:"
	@echo "   make cluster-create               -- Create GKE control plane only"
	@echo "   make cluster-nodepool-tpu         -- Add TPU node pool to existing cluster"
	@echo "   make cluster-nodepool-gpu         -- Add GPU node pool to existing cluster"
	@echo "   make cluster-credentials          -- Get kubectl credentials"
	@echo "   make cluster-scale-down           -- Scale accelerator pool to 0 (cost savings)"
	@echo "   make cluster-scale-up             -- Scale accelerator pool to NUM_NODES"
	@echo "   make cluster-clean                -- Delete cluster and cleanup"
	@echo ""
	@echo "GPU Operator:"
	@echo "   make deploy-gpu-operator          -- Deploy NVIDIA GPU Operator"
	@echo ""
	@echo "Configuration Variables:"
	@echo "   PROJECT_ID=$(PROJECT_ID)"
	@echo "   CLUSTER_NAME=$(CLUSTER_NAME)"
	@echo "   ZONE=$(ZONE)"
	@echo "   ACCELERATOR=$(ACCELERATOR)"
	@echo "   NUM_NODES=$(NUM_NODES)"
	@echo ""
	@echo "Examples:"
	@echo "   make cluster-tpu ZONE=us-east5-a NUM_NODES=1"
	@echo "   make cluster-gpu PROJECT_ID=my-project"
	@echo "   make cluster-scale-down ACCELERATOR=tpu"

check-deps:
	@echo "Checking required tools..."
	@which gcloud > /dev/null || { echo "Error: gcloud not found. Install from: https://cloud.google.com/sdk/docs/install" ; exit 1; }
	@which kubectl > /dev/null || { echo "Error: kubectl not found. Install from: https://kubernetes.io/docs/tasks/tools/" ; exit 1; }
	@which helm > /dev/null || { echo "Error: helm not found. Install from: https://helm.sh/docs/intro/install/" ; exit 1; }
	@echo "✓ All required tools present"
	@echo "Checking gcloud authentication..."
	@gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>&1 | grep -q @ || { echo "Error: Not authenticated with gcloud. Run: gcloud auth login" ; exit 1; }
	@echo "✓ Authenticated with gcloud"

check: check-deps
	@./scripts/preflight-check.sh --zone $(ZONE) --accelerator $(ACCELERATOR) --customer

cluster-credentials:
	@echo "Getting cluster credentials..."
	@test -n "$(PROJECT_ID)" || { echo "Error: PROJECT_ID not set. Run: gcloud config set project YOUR_PROJECT_ID" ; exit 1; }
	@gcloud container clusters get-credentials $(CLUSTER_NAME) \
		--zone $(ZONE) \
		--project $(PROJECT_ID) || { echo "Error: Failed to get credentials for cluster $(CLUSTER_NAME)" ; exit 1; }
	@echo "✓ kubectl configured for cluster $(CLUSTER_NAME)"

cluster-nodepool-tpu:
	@echo "Creating TPU node pool $(TPU_NODEPOOL_NAME)..."
	@echo "This will take ~10-15 minutes..."
	@test -n "$(PROJECT_ID)" || { echo "Error: PROJECT_ID not set" ; exit 1; }
	@test -n "$(CLUSTER_NAME)" || { echo "Error: CLUSTER_NAME not set" ; exit 1; }
	@gcloud container node-pools create $(TPU_NODEPOOL_NAME) \
		--cluster $(CLUSTER_NAME) \
		--zone $(ZONE) \
		--machine-type $(TPU_MACHINE_TYPE) \
		--num-nodes $(NUM_NODES) \
		--project $(PROJECT_ID) || \
		{ echo "Error: Failed to create TPU node pool. Check zone capacity and quota." ; exit 1; }
	@echo "✓ TPU node pool created"

cluster-nodepool-gpu:
	@echo "Creating GPU node pool $(GPU_NODEPOOL_NAME)..."
	@echo "This will take ~5-10 minutes..."
	@test -n "$(PROJECT_ID)" || { echo "Error: PROJECT_ID not set" ; exit 1; }
	@test -n "$(CLUSTER_NAME)" || { echo "Error: CLUSTER_NAME not set" ; exit 1; }
	@gcloud container node-pools create $(GPU_NODEPOOL_NAME) \
		--cluster $(CLUSTER_NAME) \
		--zone $(ZONE) \
		--machine-type $(GPU_MACHINE_TYPE) \
		--accelerator type=$(GPU_ACCELERATOR),count=1 \
		--num-nodes $(NUM_NODES) \
		--project $(PROJECT_ID) || \
		{ echo "Error: Failed to create GPU node pool. Check zone capacity and quota." ; exit 1; }
	@echo "✓ GPU node pool created"

cluster-create: check
	@echo "Creating GKE cluster $(CLUSTER_NAME)..."
	@./scripts/create-gke-cluster.sh \
		--$(ACCELERATOR) \
		--project $(PROJECT_ID) \
		--zone $(ZONE) \
		--cluster-name $(CLUSTER_NAME) \
		--num-nodes $(NUM_NODES) \
		--non-interactive \
		--skip-validation
	@echo "✓ Cluster creation complete"

deploy-gpu-operator:
	@echo "Checking for GPU nodes..."
	@kubectl get nodes -l cloud.google.com/gke-accelerator --no-headers 2>/dev/null | grep -q . || \
		{ echo "Error: No GPU nodes found. Create GPU node pool first with 'make cluster-nodepool-gpu'" ; exit 1; }
	@echo "Labeling GPU nodes to disable GKE default plugin..."
	@kubectl label nodes -l cloud.google.com/gke-accelerator \
		gke-no-default-nvidia-gpu-device-plugin=true --overwrite || \
		{ echo "Error: Failed to label GPU nodes" ; exit 1; }
	@echo "Creating gpu-operator namespace..."
	@kubectl create namespace gpu-operator --dry-run=client -o yaml | kubectl apply -f - || \
		{ echo "Error: Failed to create namespace" ; exit 1; }
	@echo "Applying ResourceQuota..."
	@kubectl apply -f deployments/gpu-operator/resourcequota-gcp-critical-pods.yaml || \
		{ echo "Error: Failed to apply ResourceQuota" ; exit 1; }
	@echo "Installing NVIDIA GPU Operator..."
	@helm repo add nvidia https://helm.ngc.nvidia.com/nvidia 2>/dev/null || true
	@helm repo update nvidia || { echo "Error: Failed to update Helm repo" ; exit 1; }
	@helm install --wait --timeout=10m -n gpu-operator \
		gpu-operator nvidia/gpu-operator \
		--version $(GPU_OPERATOR_VERSION) \
		--set driver.enabled=false \
		--set hostPaths.driverInstallDir=/home/kubernetes/bin/nvidia \
		--set toolkit.installDir=/home/kubernetes/bin/nvidia \
		--set cdi.enabled=true \
		--set toolkit.env[0].name=RUNTIME_CONFIG_SOURCE \
		--set toolkit.env[0].value=file \
		--set dcgmExporter.enabled=false || \
		{ echo "Error: Failed to install GPU Operator" ; exit 1; }
	@echo "Verifying GPU Operator deployment..."
	@kubectl wait --for=condition=Ready pods \
		-l app.kubernetes.io/name=gpu-operator \
		-n gpu-operator --timeout=300s || \
		{ echo "Error: GPU Operator pods failed to become ready" ; exit 1; }
	@kubectl wait --for=condition=Ready pods \
		-l app=nvidia-container-toolkit-daemonset \
		-n gpu-operator --timeout=300s || \
		{ echo "Error: NVIDIA container toolkit daemonset failed to become ready" ; exit 1; }
	@echo "✓ GPU Operator deployed successfully"

cluster-tpu: ACCELERATOR=tpu
cluster-tpu: check cluster-create cluster-nodepool-tpu cluster-credentials
	@echo "========================================="
	@echo "✓ TPU cluster ready!"
	@echo "========================================="
	@echo "Cluster: $(CLUSTER_NAME)"
	@echo "Zone: $(ZONE)"
	@echo "Nodes: $(NUM_NODES)"
	@echo ""
	@echo "Next steps:"
	@echo "  1. Install operators: make -C /path/to/rhaii-on-xks deploy-all"
	@echo "  2. Deploy LLMInferenceService: kubectl apply -f deployments/istio-kserve/caching-pattern/manifests/llmisvc-tpu-caching.yaml"

cluster-gpu: ACCELERATOR=gpu
cluster-gpu: check cluster-create cluster-nodepool-gpu cluster-credentials deploy-gpu-operator
	@echo "========================================="
	@echo "✓ GPU cluster ready!"
	@echo "========================================="
	@echo "Cluster: $(CLUSTER_NAME)"
	@echo "Zone: $(ZONE)"
	@echo "Nodes: $(NUM_NODES)"
	@echo ""
	@echo "Next steps:"
	@echo "  1. Install operators: make -C /path/to/rhaii-on-xks deploy-all"
	@echo "  2. Deploy LLMInferenceService: kubectl apply -f deployments/istio-kserve/caching-pattern/manifests/llmisvc-gpu-caching.yaml"

cluster-scale-down:
	@test -n "$(PROJECT_ID)" || { echo "Error: PROJECT_ID not set" ; exit 1; }
	@test "$(ACCELERATOR)" = "tpu" -o "$(ACCELERATOR)" = "gpu" || { echo "Error: ACCELERATOR must be 'tpu' or 'gpu'" ; exit 1; }
	@echo "Scaling $(ACCELERATOR) node pool to 0..."
	@gcloud container clusters resize $(CLUSTER_NAME) \
		--node-pool $(ACCELERATOR)-pool \
		--num-nodes 0 \
		--zone $(ZONE) \
		--project $(PROJECT_ID) \
		--quiet || { echo "Error: Failed to scale down node pool" ; exit 1; }
	@echo "✓ Node pool scaled to 0 (cost savings mode)"

cluster-scale-up:
	@test -n "$(PROJECT_ID)" || { echo "Error: PROJECT_ID not set" ; exit 1; }
	@test "$(ACCELERATOR)" = "tpu" -o "$(ACCELERATOR)" = "gpu" || { echo "Error: ACCELERATOR must be 'tpu' or 'gpu'" ; exit 1; }
	@echo "WARNING: Scaling up will incur costs (~$$1.28/hour per TPU node, ~$$0.35/hour per GPU node)"
	@echo "Scaling $(ACCELERATOR) node pool to $(NUM_NODES)..."
	@gcloud container clusters resize $(CLUSTER_NAME) \
		--node-pool $(ACCELERATOR)-pool \
		--num-nodes $(NUM_NODES) \
		--zone $(ZONE) \
		--project $(PROJECT_ID) \
		--quiet || { echo "Error: Failed to scale up node pool" ; exit 1; }
	@echo "✓ Node pool scaled to $(NUM_NODES)"

cluster-clean:
	@echo "Deleting GKE cluster $(CLUSTER_NAME)..."
	@gcloud container clusters delete $(CLUSTER_NAME) \
		--zone $(ZONE) \
		--project $(PROJECT_ID) \
		--quiet
	@echo "Cleaning up local kubeconfig..."
	@kubectl config delete-cluster gke_$(PROJECT_ID)_$(ZONE)_$(CLUSTER_NAME) 2>/dev/null || true
	@kubectl config delete-context gke_$(PROJECT_ID)_$(ZONE)_$(CLUSTER_NAME) 2>/dev/null || true
	@echo "Cleaning up Helm repositories..."
	@helm repo remove nvidia 2>/dev/null || true
	@echo "✓ Cleanup complete"

clean: cluster-clean
