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
