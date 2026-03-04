# RHAII on GKE — Documentation

Documentation for creating GKE clusters for Red Hat AI Inference Services (RHAII) workloads.

## Setup

- [Prerequisites](prerequisites.md) — Tools, accounts, and quota requirements
- [Environment Setup](environment-setup.md) — Optional environment variable configuration
- [Makefile Usage](makefile-usage.md) — Makefile targets and variables reference

## Scripts

| Script | Purpose |
|--------|---------|
| `create-gke-cluster.sh` | Automated cluster creation with integrated validation |
| `delete-gke-cluster.sh` | Safe cluster deletion or scale-to-zero |
| `preflight-check.sh` | Prerequisite validation |
| `check-accelerator-availability.sh` | Zone and quota validation |
| `check-nodepool-prerequisites.sh` | Node pool compatibility check |

## After Cluster Creation

Operator installation and workload deployment are in [rhaii-on-xks-gke-private](https://github.com/johnahull/rhaii-on-xks-gke-private).

## Troubleshooting

- [Troubleshooting](troubleshooting.md) — Common cluster creation issues and solutions

## External Resources

- [RHAII on XKS](https://github.com/opendatahub-io/rhaii-on-xks) — Operator installation
- [GKE AI Labs](https://gke-ai-labs.dev) — Google Cloud AI on GKE resources
