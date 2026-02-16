# Prerequisites

Everything you need before deploying RHAII on GKE.

## Required Accounts and Access

### Google Cloud Platform

- **GCP Account:** Active account with billing enabled
- **Project:** Existing GCP project with appropriate quotas
  - Recommended: Create new project for RHAII deployments
  - Required permissions: Owner or Editor role
- **Billing:** Enabled with valid payment method
  - Estimate: $80-$400/day depending on deployment

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

**Single-Model Deployment (4 chips):**
- TPU v6e: 4 chips in selected region
- Example: `TPUs (v6e)` in `us-central1`

**Scale-Out Deployment (12 chips):**
- TPU v6e: 12 chips minimum (for 3-node deployment)

**How to request:**
1. Navigate to: https://console.cloud.google.com/iam-admin/quotas
2. Search: "TPU v6e" and select region (e.g., us-central1)
3. Click "EDIT QUOTAS"
4. Request: 12 chips (allows both single and scale-out)
5. Justification: "LLM inference deployment for production workloads"
6. Submit request

**Approval time:** Usually 24-48 hours

### GPU Deployment Quotas

**Single-Model Deployment (1 GPU):**
- GPU T4: 1 GPU in selected region
- Example: `NVIDIA T4 GPUs` in `us-central1`

**Scale-Out Deployment (3 GPUs):**
- GPU T4: 3 GPUs minimum

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
1. `us-central1-b` (Central US) ⭐ Best availability
2. `us-south1-a` (Dallas)
3. `us-south1-b` (Dallas)
4. `us-east5-a` (Columbus)
5. `us-east5-b` (Columbus)

**Check availability:**
```bash
./scripts/check-accelerator-availability.sh --type tpu --customer
```

### GPU Zones

**Recommended zones for T4 GPUs:**
1. `us-central1-a` (Central US) ⭐ Currently used
2. `us-central1-b/c/f` (Central US)
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
# Clone llm-d-xks-gke repository
cd ~/workspace
git clone https://github.com/YOUR_ORG/llm-d-xks-gke.git
cd llm-d-xks-gke

# Clone RHAII on XKS repository (for operators)
cd ~/workspace
git clone https://github.com/opendatahub-io/rhaii-on-xks.git
```

**Directory structure:**
```
~/workspace/
├── llm-d-xks-gke/         # This repository
└── rhaii-on-xks/          # Operator installation
```

### Add Secrets

```bash
cd ~/workspace/llm-d-xks-gke

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
cd ~/workspace/llm-d-xks-gke

# For TPU deployment
./scripts/preflight-check.sh \
  --deployment istio-kserve/baseline-pattern \
  --accelerator tpu \
  --zone us-central1-b \
  --customer

# For GPU deployment
./scripts/preflight-check.sh \
  --deployment istio-kserve/baseline-pattern \
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
- ✅ RHAII on XKS repository cloned

**Success criteria:** All checks pass before proceeding to cluster creation.

---

## Estimated Time and Costs

### Setup Time
- Account setup: 1-2 hours (one-time)
- Tool installation: 15-30 minutes (one-time)
- Quota requests: 24-48 hours wait (one-time)
- Secret creation: 15 minutes (one-time)

### Deployment Costs

**TPU Deployments:**
- Single-model: ~$132/day ($3,960/month)
- Scale-out (3x): ~$377/day ($11,310/month)

**GPU Deployments:**
- Single-model: ~$80/day ($2,400/month)
- Scale-out (3x): ~$228/day ($6,840/month)

**Scaled to Zero:**
- Both: ~$6/day ($180/month) - cluster overhead only

---

## Next Steps

After completing prerequisites:

1. **TPU Deployment:** Follow [TPU Quickstart](quickstart-tpu.md)
2. **GPU Deployment:** Follow [GPU Quickstart](quickstart-gpu.md)

**Questions?** See [FAQ](faq.md) or [Troubleshooting](troubleshooting.md)
