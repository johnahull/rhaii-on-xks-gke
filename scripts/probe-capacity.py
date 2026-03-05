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

DEFAULT_GPU_ZONES = [
    "europe-west4-a",
    "us-central1-a",
    "us-central1-b",
    "us-east1-b",
    "us-east4-a",
]

DEFAULT_TPU_ZONES = [
    "europe-west4-a",
    "us-south1-a",
    "us-east5-a",
    "us-central1-b",
    "us-east1-d",
]

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


def probe_gpu_zone(zone, project):
    name = f"rhaii-probe-{zone.replace('-', '')[:15]}-{int(time.time()) % 10000}"
    cmd = [
        "gcloud", "compute", "instances", "create", name,
        f"--zone={zone}",
        "--machine-type=n1-standard-1",
        "--accelerator=type=nvidia-tesla-t4,count=1",
        "--maintenance-policy=TERMINATE",
        "--no-restart-on-failure",
        "--image-family=debian-12",
        "--image-project=debian-cloud",
        "--boot-disk-size=10GB",
        f"--project={project}",
        "--quiet",
    ]
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


def probe_tpu_zone(zone, project):
    name = f"rhaii-probe-{zone.replace('-', '')[:15]}-{int(time.time()) % 10000}"
    cmd = [
        "gcloud", "compute", "tpus", "tpu-vm", "create", name,
        f"--zone={zone}",
        "--accelerator-type=v6e-1",
        "--version=v2-alpha-tpuv6e",
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


def probe(accelerator, zones, project):
    fn = probe_gpu_zone if accelerator == "gpu" else probe_tpu_zone
    label = "GPU T4" if accelerator == "gpu" else "TPU v6e"
    icons = {"AVAILABLE": "✅", "STOCKOUT": "❌", "ERROR": "⚠️ "}

    print(f"{label} capacity ({len(zones)} zones in parallel):")
    results = {}
    with ThreadPoolExecutor(max_workers=len(zones)) as executor:
        futures = {executor.submit(fn, z, project): z for z in zones}
        for future in as_completed(futures):
            zone, status = future.result()
            results[zone] = status
            print(f"  {icons.get(status, '?')} {status:<10} {zone}", flush=True)

    available = [z for z, s in results.items() if s == "AVAILABLE"]
    if available:
        print(f"\n  Capacity confirmed: {available[0]}")
    else:
        print(f"\n  No capacity found in probed zones.")
        print(f"  Try: ./scripts/check-accelerator-availability.sh --{accelerator}")
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
    parser.add_argument("--tpu", action="store_true", help="Probe TPU v6e zones")
    parser.add_argument("--gpu", action="store_true", help="Probe GPU T4 zones")
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
        if args.zone:
            zones = [args.zone]
        else:
            zones = [z for z in DEFAULT_GPU_ZONES if z != args.exclude_zone]
        available = probe("gpu", zones, project)
        if available:
            any_available = True

    if args.tpu:
        if args.zone:
            zones = [args.zone]
        else:
            zones = [z for z in DEFAULT_TPU_ZONES if z != args.exclude_zone]
        available = probe("tpu", zones, project)
        if available:
            any_available = True

    print("=========================================")
    sys.exit(0 if any_available else 1)


if __name__ == "__main__":
    main()
