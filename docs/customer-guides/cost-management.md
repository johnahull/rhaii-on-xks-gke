# Cost Management

Strategies to optimize and control RHAII deployment costs on GKE.

## Cost Overview

### Single-Model Deployment

**TPU v6e (us-central1-b):**
- Running: ~$132/day ($3,960/month)
- Scaled to zero: ~$6/day ($180/month)

**GPU T4 (us-central1-a):**
- Running: ~$80/day ($2,400/month)
- Scaled to zero: ~$6/day ($180/month)

### Scale-Out Deployment (3 replicas)

**TPU v6e:**
- Running: ~$377/day ($11,310/month)
- Scaled to zero: ~$6/day ($180/month)

**GPU T4:**
- Running: ~$228/day ($6,840/month)
- Scaled to zero: ~$6/day ($180/month)

---

## Cost Calculator

Use the cost estimator script for detailed breakdowns:

```bash
# Single-model TPU cost
./scripts/cost-estimator.sh \
  --deployment single-model \
  --accelerator tpu

# Scale-out GPU cost
./scripts/cost-estimator.sh \
  --deployment scale-out \
  --accelerator gpu

# Compare deployment types
./scripts/cost-estimator.sh \
  --accelerator tpu \
  --compare

# Cost per request at specific traffic
./scripts/cost-estimator.sh \
  --deployment single-model \
  --accelerator tpu \
  --traffic 5  # req/s
```

---

## Immediate Cost Savings

### 1. Scale to Zero When Not in Use

**Highest impact cost saving: ~$126/day (TPU) or ~$74/day (GPU)**

**Using the automation script (recommended):**

```bash
# Scale to zero with confirmation
./scripts/delete-gke-cluster.sh \
  --cluster-name rhaii-cluster \
  --zone us-central1-b \
  --scale-to-zero

# Or using environment variables
export CLUSTER_NAME=rhaii-cluster
export ZONE=us-central1-b
./scripts/delete-gke-cluster.sh --scale-to-zero
```

**Manual scaling:**

```bash
# TPU deployment
gcloud container clusters resize rhaii-cluster \
  --node-pool tpu-pool \
  --num-nodes 0 \
  --zone us-central1-b

# GPU deployment
gcloud container clusters resize rhaii-cluster \
  --node-pool gpu-pool \
  --num-nodes 0 \
  --zone us-central1-a
```

**When scaled to zero:**
- Accelerator costs: $0
- Cluster overhead: ~$6/day (control plane + standard nodes)
- **Savings: 95%**

**Scale back up when needed:**
```bash
gcloud container clusters resize rhaii-cluster \
  --node-pool tpu-pool \
  --num-nodes 1 \
  --zone us-central1-b
```

**Startup time:** 5-10 minutes

---

### 2. Delete Cluster When Not Needed

**For long-term non-use (>1 week):**

**Using the automation script (recommended):**

```bash
# Delete with safety confirmation
./scripts/delete-gke-cluster.sh \
  --cluster-name rhaii-cluster \
  --zone us-central1-b

# Or using environment variables
export CLUSTER_NAME=rhaii-cluster
export ZONE=us-central1-b
./scripts/delete-gke-cluster.sh

# Force delete without confirmation (use with caution)
./scripts/delete-gke-cluster.sh --force
```

**Manual deletion:**

```bash
# Delete entire cluster
gcloud container clusters delete rhaii-cluster \
  --zone us-central1-b

# Saves: 100% of costs
# Startup time when recreated: ~30-40 minutes
```

**Use when:**
- Pausing project for extended period
- Completed testing phase
- Migrating to different configuration

**Recreate easily:**
```bash
./scripts/create-gke-cluster.sh --tpu
```

---

## Scheduled Scaling

### Automatic Scale Down Overnight

**Use case:** Development clusters that don't need 24/7 availability

**Cron job to scale down at 6 PM:**
```bash
0 18 * * * gcloud container clusters resize rhaii-cluster \
  --node-pool tpu-pool --num-nodes 0 --zone us-central1-b --quiet
```

**Scale up at 8 AM:**
```bash
0 8 * * 1-5 gcloud container clusters resize rhaii-cluster \
  --node-pool tpu-pool --num-nodes 1 --zone us-central1-b --quiet
```

**Savings:** ~12 hours/day × $5.50/hour = ~$66/day

---

### Weekend Shutdown

**Scale down Friday evening, scale up Monday morning:**

```bash
# Friday 6 PM - scale to zero
0 18 * * 5 gcloud container clusters resize rhaii-cluster \
  --node-pool tpu-pool --num-nodes 0 --zone us-central1-b --quiet

# Monday 8 AM - scale back up
0 8 * * 1 gcloud container clusters resize rhaii-cluster \
  --node-pool tpu-pool --num-nodes 1 --zone us-central1-b --quiet
```

**Savings:** ~2.5 days/week × $132/day = ~$330/week = ~$1,320/month

---

## Right-Sizing Strategies

### 1. Use GPU for Development, TPU for Production

**Development workflow:**
1. Develop on GPU T4: ~$80/day
2. Test on GPU with small traffic
3. Deploy to TPU for production: ~$132/day

**Savings:** ~$52/day during development (vs always using TPU)

---

### 2. Model Selection

**Use smallest model that meets requirements:**

| Model | Size | Memory | TPU Cost/Day | GPU Cost/Day |
|-------|------|--------|--------------|--------------|
| gemma-2b-it | 2B | ~4 GiB | $132 | $80 |
| mistral-7b | 7B | ~14 GiB | $132 | $80 (tight fit) |
| gemma-2-9b | 9B | ~18 GiB | $132 | Won't fit on T4 |

**Recommendation:** Start with 2B model, upgrade only if performance requirements demand it.

---

### 3. Deployment Pattern Selection

**Traffic-based decision:**

| Traffic | Recommended Pattern | TPU Cost | GPU Cost |
|---------|-------------------|----------|----------|
| <5 req/s | Single-model | $132/day | $80/day |
| 5-10 req/s | Single-model | $132/day | $80/day |
| 10-20 req/s | Scale-out (3x) | $377/day | $228/day |
| >20 req/s | Scale-out (5x) | $628/day | $380/day |

**Over-provisioning waste:** Running scale-out for <10 req/s wastes ~$245/day (TPU)

---

## Auto-Scaling with HPA

### Configure Horizontal Pod Autoscaler

**Scale based on CPU utilization:**

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: vllm-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: vllm-deployment
  minReplicas: 1
  maxReplicas: 3
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
```

**Apply:**
```bash
kubectl apply -f hpa.yaml
```

**Benefits:**
- Scale up during traffic spikes
- Scale down during low traffic
- Pay only for what you use

**Cost impact:** Variable, optimizes for actual load

---

## GCP Committed Use Discounts

### For Long-Term Deployments

**Commitment levels:**
- 1-year commitment: ~30% discount
- 3-year commitment: ~50-70% discount

**Applies to:**
- Compute resources (CPUs, memory)
- GPUs
- TPUs (limited availability)

**Example savings (3-year GPU commitment):**
- Original: $80/day = $29,200/year
- With 50% discount: $40/day = $14,600/year
- **Savings: $14,600/year**

**Purchase:**
1. Navigate to: https://console.cloud.google.com/compute/commitments
2. Select resource type (CPU, GPU)
3. Choose commitment duration
4. Review discount and confirm

**Recommendation:** Only commit if deployment is stable and long-term.

---

## Monitoring and Alerts

### Set Up Budget Alerts

**Create budget in GCP Console:**

1. Navigate to: https://console.cloud.google.com/billing/budgets
2. Create budget for project
3. Set amount (e.g., $5,000/month)
4. Configure alerts at 50%, 90%, 100%
5. Add email notification

**Alert thresholds:**
- 50% ($2,500): Review usage
- 90% ($4,500): Consider scaling down
- 100% ($5,000): Immediate action

---

### Monitor Resource Usage

**Daily checks:**
```bash
# Node resource usage
kubectl top nodes

# Pod resource usage
kubectl top pods -l serving.kserve.io/inferenceservice

# Check node pool size
gcloud container node-pools describe tpu-pool \
  --cluster rhaii-cluster \
  --zone us-central1-b \
  --format="value(initialNodeCount)"
```

**Weekly review:**
1. Check GCP billing dashboard
2. Review traffic patterns
3. Identify optimization opportunities
4. Adjust replica count if needed

---

## Cost Optimization Checklist

**Before deployment:**
- [ ] Choose appropriate accelerator (GPU for dev, TPU for prod)
- [ ] Select smallest model that meets requirements
- [ ] Request minimum quota needed
- [ ] Estimate monthly costs with traffic projections

**During deployment:**
- [ ] Start with single-model, scale only when needed
- [ ] Monitor resource utilization
- [ ] Set up budget alerts
- [ ] Document scaling procedures

**Ongoing:**
- [ ] Scale to zero when not in use
- [ ] Review monthly billing
- [ ] Optimize based on traffic patterns
- [ ] Consider committed use discounts for stable workloads

---

## Cost Comparison Examples

### Scenario 1: Development Workflow

**Requirements:** 8-hour workday, 5 days/week

**Option A: Always running (GPU)**
- Cost: $80/day × 30 days = $2,400/month

**Option B: Scheduled scaling (8 hours/day, 5 days/week)**
- Running: 40 hours/week × 4.3 weeks = 172 hours/month
- Cost: 172 hours × $3.33/hour = $573/month
- **Savings: $1,827/month (76%)**

---

### Scenario 2: Production Deployment

**Requirements:** 24/7 availability, 15 req/s traffic

**Option A: Scale-out TPU (always on)**
- Cost: $377/day × 30 days = $11,310/month
- Performance: ~25 req/s capacity

**Option B: Single-model TPU with HPA (scale up during peaks)**
- Base cost: $132/day × 30 days = $3,960/month
- Peak hours (8h/day): $245/day × 30 days = $7,350/month
- Average: ~$5,655/month
- **Savings: $5,655/month (50%)**
- **Trade-off:** Slower response during peak scaling

---

## Cost Monitoring Tools

### GCP Cost Management

**Dashboard:** https://console.cloud.google.com/billing

**Enable detailed cost tracking:**
1. Cost breakdown by service
2. Cost trends over time
3. Forecasted costs
4. Cost allocation by labels

**Add labels to resources:**
```bash
gcloud container clusters update rhaii-cluster \
  --update-labels=environment=production,team=ml-ops \
  --zone us-central1-b
```

---

### Third-Party Tools

**Kubecost (Kubernetes cost monitoring):**
- Install in cluster
- Per-pod cost breakdown
- Rightsizing recommendations
- Savings opportunities

**Installation:**
```bash
kubectl create namespace kubecost
helm install kubecost kubecost/cost-analyzer \
  --namespace kubecost
```

---

## Summary

**Highest-impact cost savings:**

1. **Scale to zero when not in use:** ~95% savings
2. **Scheduled scaling (overnight/weekends):** ~50-76% savings
3. **Use GPU for dev, TPU for prod:** ~$52/day savings
4. **Right-size deployment pattern:** Avoid over-provisioning
5. **Committed use discounts:** 30-70% for long-term

**Monthly cost examples:**
- Development (GPU, 8h/day, 5d/week): ~$573/month
- Production (TPU, 24/7, single-model): ~$3,960/month
- Production (TPU, 24/7, scale-out): ~$11,310/month

**Tools:**
```bash
./scripts/cost-estimator.sh --deployment single-model --accelerator tpu
```

---

**Questions?** See [FAQ](faq.md) or [Troubleshooting](troubleshooting.md)
