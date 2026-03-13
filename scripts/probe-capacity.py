#!/usr/bin/env python3
"""
Real-time GKE accelerator capacity prober.

Uses gcloud compute instances create (GPU) and gcloud compute tpus tpu-vm create (TPU)
with --no-restart-on-failure to detect stockouts in seconds rather than waiting 35+ minutes
for a GKE node pool creation to fail.

Lesson from dra-test/nvidia: compute instance creation fails instantly on STOCKOUT;
GKE node pools silently retry for ~35 minutes before surfacing the same error.

Zone discovery is always dynamic (via gcloud API) so the probe stays accurate as machine
types move between zones over time. No hardcoded zone lists.
"""

import argparse
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed

# GPU configs.
# - machine_type: instance type used for the probe
# - accelerator:  --accelerator flag value for gcloud instances create, or None for
#                 machine families that include the GPU (a2/g2/a3)
# - gcloud_name:  name used with `gcloud compute accelerator-types list` for zone
#                 discovery; None means discover by machine_type instead
GPU_CONFIGS = {
    "t4": {
        "label": "GPU T4",
        "machine_type": "n1-standard-1",
        "accelerator": "type=nvidia-tesla-t4,count=1",
        "gcloud_name": "nvidia-tesla-t4",
    },
    "a100": {
        "label": "GPU A100",
        "machine_type": "a2-highgpu-1g",
        "accelerator": None,
        "gcloud_name": None,  # a2 machine type IS the A100; discover by machine type
    },
    "l4": {
        "label": "GPU L4",
        "machine_type": "g2-standard-4",
        "accelerator": None,
        "gcloud_name": None,
    },
    "h100": {
        "label": "GPU H100",
        "machine_type": "a3-highgpu-1g",
        "accelerator": None,
        "gcloud_name": None,
    },
}

# TPU configs.
# - accelerator_type: passed to --accelerator-type in tpu-vm create (topology)
# - version:          passed to --version in tpu-vm create
# - gcloud_name:      name used with `gcloud compute accelerator-types list` for zone
#                     discovery (family name, different from topology identifier)
TPU_CONFIGS = {
    "v6e": {
        "label": "TPU v6e",
        "accelerator_type": "v6e-1",
        "version": "v2-alpha-tpuv6e",
        "gcloud_name": "tpu-v6e-slice",
    },
    "v5e": {
        "label": "TPU v5e",
        "accelerator_type": "v5e-1",
        "version": "v2-alpha-tpuv5e",
        "gcloud_name": "tpu-v5e",
    },
    "v5p": {
        "label": "TPU v5p",
        "accelerator_type": "v5p-1",
        "version": "v2-alpha-tpuv5p",
        "gcloud_name": "tpu-v5p-slice",
    },
}

# Recommended primary zones for capacity probing (most reliable, checked first)
DEFAULT_PRIMARY_ZONES = {
    "tpu": {
        "v6e": "europe-west4-a",  # Most reliable TPU v6e zone
        "v5e": "us-central1-a",
        "v5p": "us-central1-a",
    },
    "gpu": {
        "t4": "us-central1-a",    # Widely used, good availability
        "a100": "us-central1-a",
        "l4": "us-central1-a",
        "h100": "us-central1-a",
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


def run_stdout(cmd):
    """Run a command and return only stdout (stderr discarded — avoids warning bleed into parsed output)."""
    result = subprocess.run(cmd, capture_output=True, text=True)
    return result.returncode, result.stdout


def is_stockout(output):
    return any(p.lower() in output.lower() for p in STOCKOUT_PATTERNS)


def delete_instance_with_retry(name, zone, project, max_attempts=3):
    """Delete a compute instance synchronously, retrying on failure.
    Warns loudly if all attempts fail so the user can clean up manually."""
    for attempt in range(1, max_attempts + 1):
        rc, _ = run([
            "gcloud", "compute", "instances", "delete", name,
            f"--zone={zone}", f"--project={project}", "--quiet",
        ])
        if rc == 0:
            return
        if attempt < max_attempts:
            time.sleep(5)
    print(
        f"  ⚠️  WARNING: Failed to delete probe instance {name} in {zone} after {max_attempts} attempts. "
        f"Delete it manually to avoid ongoing charges: "
        f"gcloud compute instances delete {name} --zone={zone} --project={project} --quiet",
        flush=True,
    )


def delete_tpu_with_retry(name, zone, project, max_attempts=3):
    """Delete a TPU VM synchronously, retrying on failure.
    Warns loudly if all attempts fail so the user can clean up manually."""
    for attempt in range(1, max_attempts + 1):
        rc, _ = run([
            "gcloud", "compute", "tpus", "tpu-vm", "delete", name,
            f"--zone={zone}", f"--project={project}", "--quiet",
        ])
        if rc == 0:
            return
        if attempt < max_attempts:
            time.sleep(5)
    print(
        f"  ⚠️  WARNING: Failed to delete probe TPU {name} in {zone} after {max_attempts} attempts. "
        f"Delete it manually to avoid ongoing charges: "
        f"gcloud compute tpus tpu-vm delete {name} --zone={zone} --project={project} --quiet",
        flush=True,
    )


def discover_zones_by_machine_type(machine_type, project):
    """Return sorted deduplicated list of zones where machine_type exists."""
    _, output = run_stdout([
        "gcloud", "compute", "machine-types", "list",
        f"--filter=name={machine_type}",
        "--format=value(zone)",
        f"--project={project}",
    ])
    return sorted(set(z for z in output.strip().splitlines() if z))


def discover_zones_by_accel_type(accel_name, project):
    """Return sorted deduplicated list of zones where an accelerator type (GPU or TPU) exists."""
    _, output = run_stdout([
        "gcloud", "compute", "accelerator-types", "list",
        f"--filter=name:{accel_name}",
        "--format=value(zone)",
        f"--project={project}",
    ])
    return sorted(set(z for z in output.strip().splitlines() if z))


def probe_gpu_zone(zone, project, machine_type, accelerator_flag):
    name = f"rhaii-probe-{zone.replace('-', '')[:15]}-{int(time.time()) % 10000}"
    cmd = [
        "gcloud", "compute", "instances", "create", name,
        f"--zone={zone}",
        f"--machine-type={machine_type}",
        "--maintenance-policy=TERMINATE",
        "--no-restart-on-failure",
        "--image-family=debian-12",
        "--image-project=debian-cloud",
        "--boot-disk-size=10GB",
        f"--project={project}",
        "--quiet",
    ]
    if accelerator_flag:
        cmd.append(f"--accelerator={accelerator_flag}")
    exit_code, output = run(cmd)
    if exit_code == 0:
        delete_instance_with_retry(name, zone, project)
        return zone, "AVAILABLE"
    elif is_stockout(output):
        return zone, "STOCKOUT"
    else:
        return zone, "ERROR"


def probe_tpu_zone(zone, project, accelerator_type, version):
    name = f"rhaii-probe-{zone.replace('-', '')[:15]}-{int(time.time()) % 10000}"
    cmd = [
        "gcloud", "compute", "tpus", "tpu-vm", "create", name,
        f"--zone={zone}",
        f"--accelerator-type={accelerator_type}",
        f"--version={version}",
        f"--project={project}",
        "--quiet",
    ]
    exit_code, output = run(cmd)
    if exit_code == 0:
        delete_tpu_with_retry(name, zone, project)
        return zone, "AVAILABLE"
    elif is_stockout(output):
        return zone, "STOCKOUT"
    else:
        return zone, "ERROR"


def run_probes(label, zones, fn, primary_zone=None):
    """
    Run fn(zone) across zones.

    If primary_zone is specified:
      1. Probe primary_zone first
      2. If it has capacity, return immediately (no other zones probed)
      3. If it's STOCKOUT/ERROR, then probe all other zones in parallel

    If primary_zone is None, probe all zones in parallel immediately.
    """
    icons = {"AVAILABLE": "✅", "STOCKOUT": "❌", "ERROR": "⚠️ "}

    if primary_zone:
        # Two-phase approach: primary zone first, then fallback to others if needed
        print(f"{label} capacity (checking primary zone: {primary_zone}):")
        zone, status = fn(primary_zone)
        print(f"  {icons.get(status, '?')} {status:<10} {zone}", flush=True)

        if status == "AVAILABLE":
            print(f"\n  ✅ Capacity confirmed in primary zone: {primary_zone}")
            print()
            return [primary_zone]

        # Primary zone failed - check other zones
        other_zones = [z for z in zones if z != primary_zone]
        if not other_zones:
            print(f"\n  ❌ No capacity in {primary_zone}, and no other zones to probe.")
            print()
            return []

        print(f"\n  Primary zone has no capacity. Checking {len(other_zones)} alternative zones...")
        print()
        zones_to_probe = other_zones
    else:
        # No primary zone - probe all zones in parallel
        zones_to_probe = zones

    print(f"{label} capacity ({len(zones_to_probe)} zones in parallel):")
    results = {}
    with ThreadPoolExecutor(max_workers=max(len(zones_to_probe), 1)) as executor:
        futures = {executor.submit(fn, z): z for z in zones_to_probe}
        for future in as_completed(futures):
            zone, status = future.result()
            results[zone] = status
            print(f"  {icons.get(status, '?')} {status:<10} {zone}", flush=True)

    available = [z for z, s in results.items() if s == "AVAILABLE"]
    if available:
        print(f"\n  ✅ Capacity confirmed: {available[0]}")
    else:
        print(f"\n  ❌ No capacity found in any probed zones.")
        print(f"  Run without --probe for a full zone list.")
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
        description="Probe real-time GKE accelerator capacity across zones in parallel.\n"
                    "Zones are discovered dynamically from the GCP API — no hardcoded lists.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # GPU T4 (default) across all zones that support it:
  probe-capacity.py --gpu

  # A100 across all zones that support a2-highgpu-1g:
  probe-capacity.py --gpu --accelerator a100

  # A100 80GB variant (overrides machine type, discovers its zones):
  probe-capacity.py --gpu --machine-type a2-ultragpu-1g

  # Specific zone only:
  probe-capacity.py --gpu --accelerator a100 --zone us-central1-b

  # TPU v6e across all zones that support it:
  probe-capacity.py --tpu

  # TPU v5e:
  probe-capacity.py --tpu --accelerator v5e
        """,
    )
    parser.add_argument("--tpu", action="store_true", help="Probe TPU zones")
    parser.add_argument("--gpu", action="store_true", help="Probe GPU zones")
    parser.add_argument(
        "--accelerator",
        help="GPU: t4 (default), a100, l4, h100 — TPU: v6e (default), v5e, v5p",
    )
    parser.add_argument(
        "--machine-type",
        help="Override GPU machine type and drive zone discovery from it "
             "(e.g. a2-ultragpu-1g). Implies --gpu. Disables --accelerator gcloud flag.",
    )
    parser.add_argument("--zone", help="Probe a specific zone only (skips discovery)")
    parser.add_argument("--exclude-zone", help="Skip this zone during discovery")
    parser.add_argument("--project", help="GCP project ID (default: from gcloud config)")
    args = parser.parse_args()

    if not args.tpu and not args.gpu and not args.machine_type:
        parser.error("Specify --tpu, --gpu, or --machine-type")

    # --machine-type implies --gpu
    if args.machine_type:
        args.gpu = True

    project = args.project or get_project()

    print("=========================================")
    print("Real-Time Capacity Probe")
    print("=========================================")
    print("Discovering zones from API, then probing in parallel.")
    print()

    any_available = False

    if args.gpu:
        accel = args.accelerator or "t4"
        if accel not in GPU_CONFIGS:
            parser.error(f"Unknown GPU accelerator '{accel}'. Choose from: {', '.join(GPU_CONFIGS)}")
        config = GPU_CONFIGS[accel]

        # --machine-type overrides config; disables the --accelerator gcloud flag
        machine_type = args.machine_type or config["machine_type"]
        accelerator_flag = None if args.machine_type else config["accelerator"]
        label = f"GPU ({machine_type})" if args.machine_type else config["label"]

        if args.zone:
            zones = [args.zone]
        else:
            print(f"  Discovering zones for {machine_type}...", end=" ", flush=True)
            if args.machine_type or config["gcloud_name"] is None:
                zones = discover_zones_by_machine_type(machine_type, project)
            else:
                zones = discover_zones_by_accel_type(config["gcloud_name"], project)
            zones = [z for z in zones if z != args.exclude_zone]
            print(f"{len(zones)} found")
            print()

        if not zones:
            print(f"  No zones found for {machine_type}. Check machine type name.")
        else:
            # Determine primary zone: explicit --zone, or default recommended zone
            primary_zone = args.zone if args.zone else DEFAULT_PRIMARY_ZONES["gpu"].get(accel)
            # Only pass primary_zone if it's in the discovered zones list
            if primary_zone and primary_zone not in zones:
                print(f"  Warning: Primary zone {primary_zone} not in discovered zones, using discovery order")
                primary_zone = None

            fn = lambda zone: probe_gpu_zone(zone, project, machine_type, accelerator_flag)
            available = run_probes(label, zones, fn, primary_zone=primary_zone)
            if available:
                any_available = True

    if args.tpu:
        accel = args.accelerator or "v6e"
        if accel not in TPU_CONFIGS:
            parser.error(f"Unknown TPU accelerator '{accel}'. Choose from: {', '.join(TPU_CONFIGS)}")
        config = TPU_CONFIGS[accel]

        if args.zone:
            zones = [args.zone]
        else:
            print(f"  Discovering zones for {config['gcloud_name']}...", end=" ", flush=True)
            zones = discover_zones_by_accel_type(config["gcloud_name"], project)
            zones = [z for z in zones if z != args.exclude_zone]
            print(f"{len(zones)} found")
            print()

        if not zones:
            print(f"  No zones found for {config['label']}.")
        else:
            # Determine primary zone: explicit --zone, or default recommended zone
            primary_zone = args.zone if args.zone else DEFAULT_PRIMARY_ZONES["tpu"].get(accel)
            # Only pass primary_zone if it's in the discovered zones list
            if primary_zone and primary_zone not in zones:
                print(f"  Warning: Primary zone {primary_zone} not in discovered zones, using discovery order")
                primary_zone = None

            fn = lambda zone: probe_tpu_zone(zone, project, config["accelerator_type"], config["version"])
            available = run_probes(config["label"], zones, fn, primary_zone=primary_zone)
            if available:
                any_available = True

    print("=========================================")
    sys.exit(0 if any_available else 1)


if __name__ == "__main__":
    main()
