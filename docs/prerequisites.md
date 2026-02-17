# Prerequisites

Everything you need before deploying RHAII on GKE.

## Required Accounts and Access

### Google Cloud Platform

- **GCP Account:** Active account with billing enabled
- **Project:** Existing GCP project with appropriate quotas
  - Recommended: Create new project for RHAII deployments
  - Required permissions: Owner or Editor role
- **Billing:** Enabled with valid payment method

### Red Hat Registry

- **Red Hat Account:** Access to registry.redhat.io
- **Pull Secret:** Registry credentials for RHAII images
  - Location: `redhat-pull-secret.yaml`
  - Format: Kubernetes secret with `.dockerconfigjson`

### HuggingFace

- **HuggingFace Account:** Free account at huggingface.co
- **Access Token:** Read token for model downloads
  - Create at: https://huggingface.co/settings/tokens
  - Permissions: Read access sufficient
  - Gated models: Accept license agreements for models you'll use

---

## Required Tools

Install these CLI tools before proceeding:

### gcloud CLI

**Purpose:** Manage GCP resources, authenticate, create clusters

**Installation:**
```bash
# Linux
curl https://sdk.cloud.google.com | bash
exec -l $SHELL

# macOS (Homebrew)
brew install google-cloud-sdk

# Verify
gcloud version
```

**Configuration:**
```bash
# Authenticate
gcloud auth login

# Set project
gcloud config set project YOUR_PROJECT_ID

# Set default zone (optional)
gcloud config set compute/zone us-central1-a
```

**Required version:** ≥ 400.0.0

### kubectl

**Purpose:** Manage Kubernetes resources

**Installation:**
```bash
# Linux
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/

# macOS (Homebrew)
brew install kubectl

# Verify
kubectl version --client
```

**Required version:** ≥ 1.28

### jq

**Purpose:** JSON parsing for automation scripts

**Installation:**
```bash
# Linux (Red Hat/Fedora)
sudo dnf install jq

# Linux (Debian/Ubuntu)
sudo apt-get install jq

# macOS (Homebrew)
brew install jq

# Verify
jq --version
```

**Required version:** ≥ 1.6

---

## GCP Quotas

Request quota increases before creating clusters:

### TPU Deployment Quotas

**Required:** 12 TPU v6e chips (3 nodes × 4 chips each)

**How to request:**
1. Navigate to: https://console.cloud.google.com/iam-admin/quotas
2. Search: "TPU v6e" and select region (e.g., us-central1)
3. Click "EDIT QUOTAS"
4. Request: 12 chips
5. Justification: "LLM inference deployment for production workloads"
6. Submit request

**Approval time:** Usually 24-48 hours

### GPU Deployment Quotas

**Required:** 3 T4 GPUs

**How to request:**
1. Navigate to: https://console.cloud.google.com/iam-admin/quotas
2. Search: "nvidia-tesla-t4" and select region
3. Click "EDIT QUOTAS"
4. Request: 3 GPUs
5. Justification: "LLM inference deployment for development/testing"
6. Submit request

**Approval time:**
- T4: Usually instant or within hours
- A100/H100: 24-48 hours

### Additional Quotas

**All Deployments:**
- CPUs: 50+ (for cluster nodes)
- In-use IP addresses: 10+
- Load balancers: 5+

---

## Required Secrets

### Red Hat Pull Secret

**File:** `redhat-pull-secret.yaml`

**Format:**
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: rhaiis-pull-secret
type: kubernetes.io/dockerconfigjson
data:
  .dockerconfigjson: <base64-encoded-credentials>
```

**How to obtain:**
1. Log in to Red Hat registry: https://registry.redhat.io
2. Navigate to: Registry Service Accounts
3. Create or use existing service account
4. Download Kubernetes secret (YAML format)

**Location:** Place in repository root directory

### HuggingFace Token Secret

**File:** `huggingface-token-secret.yaml`

**Format:**
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: huggingface-token
type: Opaque
stringData:
  token: YOUR_HF_TOKEN_HERE
```

**How to create:**
1. Get token from: https://huggingface.co/settings/tokens
2. Create secret file with token value
3. Accept license for models you'll use (e.g., google/gemma-2b-it)

**Location:** Place in repository root directory

---

## Zone Selection

### TPU Zones

**Recommended zones for TPU v6e:**
1. `europe-west4-a` (Netherlands) ⭐ Most reliable
2. `us-south1-a` (Dallas)
3. `us-east5-a` (Columbus)
4. `europe-west4-a` (Central US)
5. `us-south1-b` (Dallas)

**Check availability:**
```bash
./scripts/check-accelerator-availability.sh --type tpu --customer
```

### GPU Zones

**Recommended zones for T4 GPUs:**
1. `europe-west4-a/b` (Netherlands) ⭐ Primary
2. `us-central1-a/b/c/f` (Central US)
3. `us-east1-b/c/d` (South Carolina)
4. `us-east4-a/b/c` (Virginia)
5. `us-west1-a/b` (Oregon)

**Check availability:**
```bash
./scripts/check-accelerator-availability.sh --type gpu --customer
```

---

## Repository Setup

### Clone Repository

```bash
# Clone rhaii-on-xks-gke repository
cd ~/workspace
git clone https://github.com/YOUR_ORG/rhaii-on-xks-gke.git
cd rhaii-on-xks-gke

# Clone RHAII on XKS repository for operator installation
# Repository: https://github.com/opendatahub-io/rhaii-on-xks
cd ~/workspace
git clone https://github.com/opendatahub-io/rhaii-on-xks.git
```

**Directory structure:**
```
~/workspace/
├── rhaii-on-xks-gke/         # This repository
└── rhaii-on-xks/          # Operator installation (https://github.com/opendatahub-io/rhaii-on-xks)
```

### Add Secrets

```bash
cd ~/workspace/rhaii-on-xks-gke

# Copy or create secret files
cp /path/to/redhat-pull-secret.yaml .
cp /path/to/huggingface-token-secret.yaml .

# Verify secrets exist
ls -l *secret.yaml
```

---

## Validation

Run the comprehensive preflight check to verify all prerequisites:

```bash
cd ~/workspace/rhaii-on-xks-gke

# For TPU deployment
./scripts/preflight-check.sh \
  --accelerator tpu \
  --zone europe-west4-a \
  --customer

# For GPU deployment
./scripts/preflight-check.sh \
  --accelerator gpu \
  --zone us-central1-a \
  --customer
```

**What it checks:**
- ✅ Tool installation (gcloud, kubectl, jq)
- ✅ GCP authentication
- ✅ IAM permissions
- ✅ Accelerator availability in zone
- ✅ Secret files exist and valid
- ✅ [RHAII on XKS](https://github.com/opendatahub-io/rhaii-on-xks) repository cloned

**Success criteria:** All checks pass before proceeding to cluster creation.

---

## Estimated Setup Time

- Account setup: 1-2 hours (one-time)
- Tool installation: 15-30 minutes (one-time)
- Quota requests: 24-48 hours wait (one-time)
- Secret creation: 15 minutes (one-time)

---

## Next Steps

After completing prerequisites:

1. **Optional:** Configure [Environment Setup](environment-setup.md) to streamline commands
2. **TPU Deployment:** Follow [RHAII Deployment Guide (TPU)](deployment-tpu.md)
3. **GPU Deployment:** Follow [RHAII Deployment Guide (GPU)](deployment-gpu.md)

**Questions?** See [Troubleshooting](troubleshooting.md)
