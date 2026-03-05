#!/usr/bin/env python3
"""
Real-time GKE accelerator capacity prober.

Uses gcloud compute instances create (GPU) and gcloud compute tpus tpu-vm create (TPU)
with --no-restart-on-failure to detect stockouts in seconds rather than waiting 35+ minutes
for a GKE node pool creation to fail.

Lesson from dra-test/nvidia: compute instance creation fails instantly on STOCKOUT;
GKE node pools silently retry for ~35 minutes before surfacing the same error.
"""

import argparse
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed

# GPU configs: machine_type is the probe instance type; accelerator is the --accelerator
# flag value (None for machine families that include the GPU, e.g. a2/g2/a3).
GPU_CONFIGS = {
    "t4": {
        "label": "GPU T4",
        "machine_type": "n1-standard-1",
        "accelerator": "type=nvidia-tesla-t4,count=1",
        "default_zones": [
            "europe-west4-a",
            "us-central1-a",
            "us-central1-b",
            "us-east1-b",
            "us-east4-a",
        ],
    },
    "a100": {
        "label": "GPU A100",
        "machine_type": "a2-highgpu-1g",
        "accelerator": None,  # A100 is part of the a2 machine family
        "default_zones": [
            "us-central1-a",
            "us-central1-b",
            "us-east1-c",
            "us-east4-a",
            "europe-west4-a",
        ],
    },
    "l4": {
        "label": "GPU L4",
        "machine_type": "g2-standard-4",
        "accelerator": None,  # L4 is part of the g2 machine family
        "default_zones": [
            "us-central1-a",
            "us-central1-b",
            "us-east1-c",
            "us-east4-a",
            "europe-west4-a",
        ],
    },
    "h100": {
        "label": "GPU H100",
        "machine_type": "a3-highgpu-1g",
        "accelerator": None,  # H100 is part of the a3 machine family
        "default_zones": [
            "us-central1-a",
            "us-central1-b",
            "us-east4-a",
            "us-west4-b",
            "europe-west4-a",
        ],
    },
}

# TPU configs: accelerator_type and version are passed to tpu-vm create.
TPU_CONFIGS = {
    "v6e": {
        "label": "TPU v6e",
        "accelerator_type": "v6e-1",
        "version": "v2-alpha-tpuv6e",
        "default_zones": [
            "europe-west4-a",
            "us-south1-a",
            "us-east5-a",
            "us-central1-b",
            "us-east1-d",
        ],
    },
    "v5e": {
        "label": "TPU v5e",
        "accelerator_type": "v5e-1",
        "version": "v2-alpha-tpuv5e",
        "default_zones": [
            "us-central1-a",
            "us-south1-a",
            "europe-west4-b",
            "us-west1-c",
            "us-west4-a",
        ],
    },
    "v5p": {
        "label": "TPU v5p",
        "accelerator_type": "v5p-1",
        "version": "v2-alpha-tpuv5p",
        "default_zones": [
            "us-central1-a",
            "us-east5-a",
            "europe-west4-b",
        ],
    },
}

STOCKOUT_PATTERNS = [
    "STOCKOUT",
    "RESOURCE_EXHAUSTED",
    "Insufficient capacity",
    "no more capacity",
    "out of capacity",
    "does not have enough resources",
    "no more resources",
]


def run(cmd):
    result = subprocess.run(cmd, capture_output=True, text=True)
    return result.returncode, result.stdout + result.stderr


def is_stockout(output):
    return any(p.lower() in output.lower() for p in STOCKOUT_PATTERNS)


def probe_gpu_zone(zone, project, config):
    name = f"rhaii-probe-{zone.replace('-', '')[:15]}-{int(time.time()) % 10000}"
    cmd = [
        "gcloud", "compute", "instances", "create", name,
        f"--zone={zone}",
        f"--machine-type={config['machine_type']}",
        "--maintenance-policy=TERMINATE",
        "--no-restart-on-failure",
        "--image-family=debian-12",
        "--image-project=debian-cloud",
        "--boot-disk-size=10GB",
        f"--project={project}",
        "--quiet",
    ]
    if config["accelerator"]:
        cmd.append(f"--accelerator={config['accelerator']}")
    exit_code, output = run(cmd)
    if exit_code == 0:
        subprocess.Popen(
            ["gcloud", "compute", "instances", "delete", name,
             f"--zone={zone}", f"--project={project}", "--quiet"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        return zone, "AVAILABLE"
    elif is_stockout(output):
        return zone, "STOCKOUT"
    else:
        return zone, "ERROR"


def probe_tpu_zone(zone, project, config):
    name = f"rhaii-probe-{zone.replace('-', '')[:15]}-{int(time.time()) % 10000}"
    cmd = [
        "gcloud", "compute", "tpus", "tpu-vm", "create", name,
        f"--zone={zone}",
        f"--accelerator-type={config['accelerator_type']}",
        f"--version={config['version']}",
        f"--project={project}",
        "--quiet",
    ]
    exit_code, output = run(cmd)
    if exit_code == 0:
        subprocess.Popen(
            ["gcloud", "compute", "tpus", "tpu-vm", "delete", name,
             f"--zone={zone}", f"--project={project}", "--quiet"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        return zone, "AVAILABLE"
    elif is_stockout(output):
        return zone, "STOCKOUT"
    else:
        return zone, "ERROR"


def probe(kind, accel, zones, project):
    """Run parallel capacity probes and print results as they arrive."""
    if kind == "gpu":
        config = GPU_CONFIGS[accel]
        fn = lambda zone: probe_gpu_zone(zone, project, config)
    else:
        config = TPU_CONFIGS[accel]
        fn = lambda zone: probe_tpu_zone(zone, project, config)

    icons = {"AVAILABLE": "✅", "STOCKOUT": "❌", "ERROR": "⚠️ "}
    print(f"{config['label']} capacity ({len(zones)} zones in parallel):")

    results = {}
    with ThreadPoolExecutor(max_workers=len(zones)) as executor:
        futures = {executor.submit(fn, z): z for z in zones}
        for future in as_completed(futures):
            zone, status = future.result()
            results[zone] = status
            print(f"  {icons.get(status, '?')} {status:<10} {zone}", flush=True)

    available = [z for z, s in results.items() if s == "AVAILABLE"]
    if available:
        print(f"\n  Capacity confirmed: {available[0]}")
    else:
        print(f"\n  No capacity found in probed zones.")
        print(f"  Try: ./scripts/check-accelerator-availability.sh --{kind}")
    print()
    return available


def get_project():
    _, output = run(["gcloud", "config", "get-value", "project"])
    project = output.strip()
    if not project:
        print("Error: PROJECT_ID not set. Run: gcloud config set project YOUR_PROJECT_ID")
        sys.exit(1)
    return project


def main():
    parser = argparse.ArgumentParser(
        description="Probe real-time GKE accelerator capacity across zones in parallel."
    )
    parser.add_argument("--tpu", action="store_true", help="Probe TPU zones")
    parser.add_argument("--gpu", action="store_true", help="Probe GPU zones")
    parser.add_argument(
        "--accelerator",
        help="Accelerator type: gpu=(t4|a100|l4|h100), tpu=(v6e|v5e|v5p). "
             "Defaults: t4 for --gpu, v6e for --tpu",
    )
    parser.add_argument("--zone", help="Probe a specific zone only")
    parser.add_argument("--exclude-zone", help="Skip this zone when probing defaults")
    parser.add_argument("--project", help="GCP project ID (default: from gcloud config)")
    args = parser.parse_args()

    if not args.tpu and not args.gpu:
        parser.error("Specify --tpu, --gpu, or both")

    project = args.project or get_project()

    print("=========================================")
    print("Real-Time Capacity Probe")
    print("=========================================")
    print("Probing in parallel — results appear as they arrive (~30-60s).")
    print()

    any_available = False

    if args.gpu:
        accel = args.accelerator or "t4"
        if accel not in GPU_CONFIGS:
            parser.error(f"Unknown GPU accelerator '{accel}'. Choose from: {', '.join(GPU_CONFIGS)}")
        config = GPU_CONFIGS[accel]
        zones = [args.zone] if args.zone else [z for z in config["default_zones"] if z != args.exclude_zone]
        available = probe("gpu", accel, zones, project)
        if available:
            any_available = True

    if args.tpu:
        accel = args.accelerator or "v6e"
        if accel not in TPU_CONFIGS:
            parser.error(f"Unknown TPU accelerator '{accel}'. Choose from: {', '.join(TPU_CONFIGS)}")
        config = TPU_CONFIGS[accel]
        zones = [args.zone] if args.zone else [z for z in config["default_zones"] if z != args.exclude_zone]
        available = probe("tpu", accel, zones, project)
        if available:
            any_available = True

    print("=========================================")
    sys.exit(0 if any_available else 1)


if __name__ == "__main__":
    main()
