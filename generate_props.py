#!/usr/bin/env python3
"""Generate prop models for Liminal horror game via Meshy API.

Generates 18 additional prop models to populate the abandoned town with
believable detail across all categories: street furniture, barriers,
vehicles, debris, interior furniture, and vegetation.

Uses Meshy-6 with low-poly settings optimized for PS1 aesthetic.

Usage:
    python3 generate_props.py

Requires MESHY_API_KEY in .env file.
"""

import json
import os
import time
import urllib.request
import urllib.error
from pathlib import Path

# ============================================================
# Configuration
# ============================================================

# Load .env (stdlib only, no pip deps -- project convention)
env = {}
with open(Path(__file__).parent / ".env") as f:
    for line in f:
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            k, v = line.split("=", 1)
            env[k] = v

MESHY_KEY = env["MESHY_API_KEY"]
BASE_DIR = Path(__file__).parent / "assets"
OUTPUT_DIR = BASE_DIR / "models" / "props"

# Meshy API endpoints
MESHY_API_BASE = "https://api.meshy.ai/openapi/v2/text-to-3d"

# Generation settings (Meshy-6 with low-poly optimization)
GENERATION_SETTINGS = {
    "mode": "preview",
    "ai_model": "meshy-6",
    "model_type": "lowpoly",
    "target_polycount": 1000,  # Budget is 500-2000 tris for props; set to 1000 since Meshy overshoots
    "topology": "triangle",
    "should_remesh": True,
}

# Shared negative prompt for all props
NEGATIVE_PROMPT = "cartoon, anime, bright, colorful, cute, high detail, photorealistic, modern, clean, new"

# Rate limiting
SUBMIT_DELAY = 1.5     # seconds between API submissions
POLL_INTERVAL = 15     # seconds between poll requests
TASK_TIMEOUT = 600     # 10 minutes max per task
RETRY_DELAY = 30       # seconds before retrying a failed task


# ============================================================
# Prop definitions
# ============================================================

# (name, category_tag, prompt)
# Only props that DON'T already exist on disk will be generated.
# Names must match validate_assets.py EXPECTED_PROPS list.
PROPS = [
    # --- Street Furniture ---
    (
        "mailbox",
        "street_furniture",
        "Old weathered US mailbox, blue paint chipping, dented, mounted on post, "
        "abandoned town, horror prop, low poly game asset",
    ),
    (
        "fire_hydrant",
        "street_furniture",
        "Rusted fire hydrant, worn red paint peeling, urban street, abandoned, "
        "horror atmosphere, low poly game asset, small object",
    ),
    (
        "phone_booth",
        "street_furniture",
        "Abandoned phone booth, cracked glass panels, receiver dangling, graffiti, "
        "weathered metal frame, horror, low poly game asset",
    ),
    (
        "trash_can",
        "street_furniture",
        "Overflowing metal trash can, dented, rust spots, garbage spilling, "
        "abandoned street, horror prop, low poly game asset",
    ),
    # --- Barriers ---
    (
        "traffic_cone",
        "barriers",
        "Faded orange traffic cone, weathered, dirty, cracked, road construction, "
        "abandoned, horror prop, low poly game asset, small object",
    ),
    (
        "road_barrier",
        "barriers",
        "Wooden road barricade with reflectors, weathered wood, faded orange stripes, "
        "abandoned roadwork, horror prop, low poly game asset",
    ),
    (
        "chain_link_fence",
        "barriers",
        "Section of chain link fence, rusted metal, bent and sagging, barbed wire top, "
        "abandoned area, horror prop, low poly game asset",
    ),
    # --- Vehicles ---
    (
        "pickup_truck",
        "vehicles",
        "Abandoned rusted pickup truck from the 1980s, flat tires, broken windshield, "
        "faded paint, overgrown weeds, horror, low poly game asset",
    ),
    (
        "police_car",
        "vehicles",
        "Abandoned police car, faded paint, broken lights, rusted, flat tires, "
        "doors open, horror atmosphere, low poly game asset",
    ),
    # --- Debris/Containers ---
    (
        "tire_stack",
        "debris",
        "Stack of old tires, rubber cracking, weathered, abandoned lot, "
        "horror prop, low poly game asset",
    ),
    # --- Interior Furniture ---
    (
        "overturned_table",
        "interior",
        "Wooden table flipped on its side, broken leg, scratched surface, "
        "abandoned interior, horror prop, low poly game asset",
    ),
    (
        "broken_chair",
        "interior",
        "Broken wooden chair, missing leg, splintered wood, abandoned room, "
        "horror atmosphere, low poly game asset",
    ),
    (
        "old_tv",
        "interior",
        "Old CRT television set from the 1980s, cracked screen, antenna ears, "
        "dusty, abandoned room, horror prop, low poly game asset",
    ),
    (
        "filing_cabinet",
        "interior",
        "Metal filing cabinet, drawers pulled open, rusted, dented, abandoned office, "
        "horror prop, low poly game asset",
    ),
    (
        "torn_couch",
        "interior",
        "Old fabric couch, torn cushions, springs visible, stained, abandoned "
        "living room, horror prop, low poly game asset",
    ),
    (
        "rusted_refrigerator",
        "interior",
        "Old refrigerator with door hanging open, rusted exterior, empty shelves, "
        "abandoned kitchen, horror prop, low poly game asset",
    ),
    (
        "fallen_bookshelf",
        "interior",
        "Wooden bookshelf fallen sideways, scattered books, broken shelves, "
        "abandoned room, horror prop, low poly game asset",
    ),
    # --- Vegetation ---
    (
        "dead_tree",
        "vegetation",
        "Bare dead tree, gnarled branches, no leaves, twisted trunk, dark bark, "
        "horror atmosphere, low poly game asset",
    ),
    (
        "overgrown_bushes",
        "vegetation",
        "Overgrown wild bushes, tangled branches, dark green foliage, unkempt, "
        "abandoned yard, low poly game asset",
    ),
]


# ============================================================
# API helpers
# ============================================================


def api_request(url, data=None, headers=None, method=None):
    """Make an API request and return parsed JSON response.

    Args:
        url: API endpoint URL
        data: Request body (dict, will be JSON-encoded)
        headers: HTTP headers dict
        method: HTTP method override

    Returns:
        Parsed JSON response dict, or None on error
    """
    if headers is None:
        headers = {}
    if data is not None and isinstance(data, dict):
        data = json.dumps(data).encode()
        headers.setdefault("Content-Type", "application/json")
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            content_type = resp.headers.get("Content-Type", "")
            body = resp.read()
            if "json" in content_type:
                return json.loads(body)
            return body
    except urllib.error.HTTPError as e:
        error_body = e.read().decode()
        print(f"  HTTP {e.code}: {error_body[:500]}")
        return None
    except (urllib.error.URLError, TimeoutError) as e:
        print(f"  Network error: {e}")
        return None


def download_file(url, path):
    """Download a file from URL to path.

    Args:
        url: Download URL
        path: Destination Path object
    """
    path.parent.mkdir(parents=True, exist_ok=True)
    urllib.request.urlretrieve(url, str(path))
    size_kb = path.stat().st_size / 1024
    print(f"  Downloaded: {path.name} ({size_kb:.0f} KB)")


# ============================================================
# Meshy API operations
# ============================================================


def create_meshy_task(name, prompt):
    """Submit a text-to-3D preview task to Meshy.

    Uses Meshy-6 with lowpoly model type and target polycount for
    PS1-style props within the 500-2000 tri budget.

    Args:
        name: Prop name (for logging)
        prompt: Text prompt describing the prop

    Returns:
        Task ID string, or None on failure
    """
    task_data = {
        **GENERATION_SETTINGS,
        "prompt": prompt,
        "negative_prompt": NEGATIVE_PROMPT,
    }

    resp = api_request(
        MESHY_API_BASE,
        data=task_data,
        headers={"Authorization": f"Bearer {MESHY_KEY}"},
    )

    if resp and "result" in resp:
        task_id = resp["result"]
        print(f"  Submitted: {name} -> Task ID: {task_id}")
        return task_id

    print(f"  FAILED to submit: {name} -> {resp}")
    return None


def poll_meshy_task(task_id, name, timeout=TASK_TIMEOUT):
    """Poll a Meshy task until completion or timeout.

    Args:
        task_id: Meshy task ID
        name: Prop name (for logging)
        timeout: Maximum wait time in seconds

    Returns:
        Task result dict on success, None on failure/timeout
    """
    start = time.time()
    while time.time() - start < timeout:
        resp = api_request(
            f"{MESHY_API_BASE}/{task_id}",
            headers={"Authorization": f"Bearer {MESHY_KEY}"},
            method="GET",
        )
        if not resp:
            time.sleep(POLL_INTERVAL)
            continue

        status = resp.get("status", "UNKNOWN")
        progress = resp.get("progress", 0)

        if status == "SUCCEEDED":
            print(f"  Completed: {name} (100%)")
            return resp
        elif status in ("FAILED", "CANCELED"):
            print(f"  {status}: {name}")
            return None

        elapsed = int(time.time() - start)
        print(f"  Polling: {name} -- {status} {progress}% ({elapsed}s)")
        time.sleep(POLL_INTERVAL)

    print(f"  TIMEOUT: {name} (>{timeout}s)")
    return None


# ============================================================
# Main generation pipeline
# ============================================================


def main():
    print("=" * 60)
    print("LIMINAL PROP GENERATION (Meshy-6)")
    print("=" * 60)

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    # --------------------------------------------------------
    # Phase 1: Determine which props need generation
    # --------------------------------------------------------
    print("\n--- Checking existing props ---")
    to_generate = []
    skipped = []

    for name, category_tag, prompt in PROPS:
        output_path = OUTPUT_DIR / f"{name}.glb"
        if output_path.exists() and output_path.stat().st_size > 1000:
            size_kb = output_path.stat().st_size / 1024
            print(f"  Skipping {name} (already exists, {size_kb:.0f}KB)")
            skipped.append(name)
        else:
            to_generate.append((name, category_tag, prompt))

    # Also count existing props not in our list (from generate_assets.py)
    existing_on_disk = {f.stem for f in OUTPUT_DIR.glob("*.glb") if f.stat().st_size > 1000}
    our_names = {name for name, _, _ in PROPS}
    pre_existing = existing_on_disk - our_names
    if pre_existing:
        print(f"\n  Pre-existing props (from earlier scripts): {', '.join(sorted(pre_existing))}")

    if not to_generate:
        print("\n  All props already exist. Nothing to generate.")
        _print_summary(skipped, [], [])
        return

    print(f"\n  Existing (our list): {len(skipped)} | To generate: {len(to_generate)}")
    print(f"  Pre-existing (other scripts): {len(pre_existing)}")

    # --------------------------------------------------------
    # Phase 2: Submit all tasks (batch submission)
    # --------------------------------------------------------
    print("\n--- Submitting generation tasks ---")
    tasks = []           # (task_id, name, category_tag, prompt)
    failed_submit = []   # names that failed to submit

    for name, category_tag, prompt in to_generate:
        task_id = create_meshy_task(name, prompt)
        if task_id:
            tasks.append((task_id, name, category_tag, prompt))
        else:
            failed_submit.append(name)
        time.sleep(SUBMIT_DELAY)  # Rate limit between submissions

    if not tasks:
        print("\n  All submissions failed. Check API key and connectivity.")
        _print_summary(skipped, [], failed_submit)
        return

    print(f"\n  Submitted: {len(tasks)} | Failed: {len(failed_submit)}")

    # --------------------------------------------------------
    # Phase 3: Poll all tasks and download results
    # --------------------------------------------------------
    print("\n--- Polling for completion ---")
    completed = []
    failed_tasks = []

    for task_id, name, category_tag, prompt in tasks:
        print(f"\n  Waiting for: {name} ({category_tag})")
        result = poll_meshy_task(task_id, name)

        if result and "model_urls" in result:
            glb_url = result["model_urls"].get("glb")
            if glb_url:
                output_path = OUTPUT_DIR / f"{name}.glb"
                try:
                    download_file(glb_url, output_path)
                    completed.append(name)
                    continue
                except Exception as e:
                    print(f"  Download failed for {name}: {e}")

        # Task failed -- attempt one retry
        print(f"  Retrying {name} after {RETRY_DELAY}s delay...")
        time.sleep(RETRY_DELAY)

        retry_task_id = create_meshy_task(name, prompt)
        if retry_task_id:
            time.sleep(SUBMIT_DELAY)
            retry_result = poll_meshy_task(retry_task_id, name)
            if retry_result and "model_urls" in retry_result:
                glb_url = retry_result["model_urls"].get("glb")
                if glb_url:
                    output_path = OUTPUT_DIR / f"{name}.glb"
                    try:
                        download_file(glb_url, output_path)
                        completed.append(name)
                        continue
                    except Exception as e:
                        print(f"  Retry download failed for {name}: {e}")

        failed_tasks.append(name)
        print(f"  FAILED (after retry): {name}")

    # --------------------------------------------------------
    # Summary
    # --------------------------------------------------------
    all_failed = failed_submit + failed_tasks
    _print_summary(skipped, completed, all_failed)


def _print_summary(skipped, completed, failed):
    """Print final summary of generation results."""
    print("\n" + "=" * 60)
    print("PROP GENERATION SUMMARY")
    print("=" * 60)

    # Count total GLBs on disk (including pre-existing from generate_assets.py)
    total_on_disk = len([f for f in OUTPUT_DIR.glob("*.glb") if f.stat().st_size > 1000])

    # Count by category
    category_counts = {}
    for name, category_tag, _ in PROPS:
        path = OUTPUT_DIR / f"{name}.glb"
        if path.exists() and path.stat().st_size > 1000:
            category_counts[category_tag] = category_counts.get(category_tag, 0) + 1

    print(f"  Already existed (skipped): {len(skipped)}")
    print(f"  Newly generated: {len(completed)}")
    print(f"  Failed: {len(failed)}")
    print(f"  Total .glb files on disk: {total_on_disk}")
    print(f"  Target: >= 20 props")
    print()

    print("  By category:")
    for cat in ["street_furniture", "barriers", "vehicles", "debris", "interior", "vegetation"]:
        count = category_counts.get(cat, 0)
        print(f"    {cat}: {count}")
    print()

    if failed:
        print(f"  Failed props: {', '.join(failed)}")
        print()

    if total_on_disk >= 20:
        print("  STATUS: TARGET MET")
    else:
        print(f"  STATUS: BELOW TARGET ({total_on_disk}/20)")
        print("  Re-run this script to retry failed props (idempotent).")

    # List all files on disk
    print("\n--- Files on disk ---")
    for glb in sorted(OUTPUT_DIR.glob("*.glb")):
        if glb.stat().st_size > 100:
            size_kb = glb.stat().st_size / 1024
            print(f"  {glb.name}: {size_kb:.0f} KB")


if __name__ == "__main__":
    main()
