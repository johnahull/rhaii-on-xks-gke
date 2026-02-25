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
