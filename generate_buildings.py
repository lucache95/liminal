#!/usr/bin/env python3
"""Generate remaining building models for Liminal horror game via Meshy API.

Generates 10-14 additional building models to cover all 12 town districts,
bringing the total to 15+ unique buildings. Uses Meshy-6 with low-poly
settings optimized for PS1 aesthetic.

Usage:
    python3 generate_buildings.py

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
OUTPUT_DIR = BASE_DIR / "models" / "environment"

# Meshy API endpoints
MESHY_API_BASE = "https://api.meshy.ai/openapi/v2/text-to-3d"

# Generation settings (Meshy-6 with low-poly optimization)
GENERATION_SETTINGS = {
    "mode": "preview",
    "ai_model": "meshy-6",
    "model_type": "lowpoly",
    "target_polycount": 3000,  # Budget is 3-5K tris; set lower since Meshy often exceeds by 50-200%
    "topology": "triangle",
    "should_remesh": True,
}

# Shared negative prompt for all buildings
NEGATIVE_PROMPT = "cartoon, anime, bright, colorful, cute, high detail, photorealistic, modern, clean"

# Rate limiting
SUBMIT_DELAY = 1       # seconds between API submissions
POLL_INTERVAL = 15     # seconds between poll requests
TASK_TIMEOUT = 600     # 10 minutes max per task
RETRY_DELAY = 30       # seconds before retrying a failed task


# ============================================================
# Building definitions
# ============================================================

# (name, district, prompt)
# Only buildings that DON'T already exist on disk will be generated.
BUILDINGS = [
    (
        "hardware_store",
        "MainStreet",
        "Abandoned small town hardware store, metal facade, broken signage, "
        "dark windows, weathered, horror atmosphere, low poly game asset",
    ),
    (
        "diner",
        "MainStreet",
        "Abandoned 1960s roadside diner, large broken windows, counter visible "
        "inside, neon sign off, weathered chrome, horror, low poly game asset",
    ),
    (
        "bar_tavern",
        "MainStreet",
        "Small town bar exterior, dark wood facade, broken neon beer sign, "
        "windowless walls, heavy wooden door, horror atmosphere, low poly game asset",
    ),
    (
        "house_ranch",
        "Residential",
        "Abandoned ranch-style single story house, attached garage, boarded "
        "windows, overgrown lawn, peeling paint, horror, low poly game asset",
    ),
    (
        "house_colonial",
        "Residential",
        "Derelict two-story colonial house, front porch, shuttered windows, "
        "weathered white siding, sagging roof, horror atmosphere, low poly game asset",
    ),
    (
        "motel",
        "Motel",
        "Abandoned L-shaped motel building, exterior corridors, numbered room "
        "doors, broken neon vacancy sign, stained stucco walls, horror, low poly game asset",
    ),
    (
        "school",
        "Church",
        "Abandoned small town schoolhouse, red brick facade, double entry doors, "
        "bell tower, broken windows, overgrown, horror atmosphere, low poly game asset",
    ),
    (
        "factory",
        "Industrial",
        "Abandoned small factory building, smokestacks, loading dock, corrugated "
        "metal, rusted, industrial horror, low poly game asset",
    ),
    (
        "radio_station",
        "RadioTower",
        "Small concrete radio station building, flat roof, antenna equipment "
        "outside, reinforced door, isolated, horror atmosphere, low poly game asset",
    ),
    (
        "ranger_station",
        "ForestEdge",
        "Wooden ranger station cabin, covered porch, forest edge, log "
        "construction, broken windows, isolated, horror atmosphere, low poly game asset",
    ),
    (
        "pharmacy",
        "MainStreet",
        "Abandoned small town pharmacy, large front window, faded cross sign, "
        "brick exterior, horror atmosphere, low poly game asset",
    ),
    (
        "trailer_home",
        "Residential",
        "Abandoned single-wide trailer home, rusted siding, broken steps, "
        "overgrown weeds, horror, low poly game asset",
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
    PS1-style buildings within the 3-5K tri budget.

    Args:
        name: Building name (for logging)
        prompt: Text prompt describing the building

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
        name: Building name (for logging)
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
    print("LIMINAL BUILDING GENERATION (Meshy-6)")
    print("=" * 60)

    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    # --------------------------------------------------------
    # Phase 1: Determine which buildings need generation
    # --------------------------------------------------------
    print("\n--- Checking existing buildings ---")
    to_generate = []
    skipped = []

    for name, district, prompt in BUILDINGS:
        output_path = OUTPUT_DIR / f"{name}.glb"
        if output_path.exists() and output_path.stat().st_size > 1000:
            size_kb = output_path.stat().st_size / 1024
            print(f"  Skipping {name} (already exists, {size_kb:.0f}KB)")
            skipped.append(name)
        else:
            to_generate.append((name, district, prompt))

    if not to_generate:
        print("\n  All buildings already exist. Nothing to generate.")
        _print_summary(skipped, [], [])
        return

    print(f"\n  Existing: {len(skipped)} | To generate: {len(to_generate)}")

    # --------------------------------------------------------
    # Phase 2: Submit all tasks (batch submission)
    # --------------------------------------------------------
    print("\n--- Submitting generation tasks ---")
    tasks = []        # (task_id, name, district, prompt)
    failed_submit = []  # names that failed to submit

    for name, district, prompt in to_generate:
        task_id = create_meshy_task(name, prompt)
        if task_id:
            tasks.append((task_id, name, district, prompt))
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

    for task_id, name, district, prompt in tasks:
        print(f"\n  Waiting for: {name} ({district})")
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
    print("GENERATION SUMMARY")
    print("=" * 60)

    # Count total GLBs on disk
    total_on_disk = len(list(OUTPUT_DIR.glob("*.glb")))

    print(f"  Already existed (skipped): {len(skipped)}")
    print(f"  Newly generated: {len(completed)}")
    print(f"  Failed: {len(failed)}")
    print(f"  Total .glb files on disk: {total_on_disk}")
    print(f"  Target: >= 15 buildings")
    print()

    if failed:
        print(f"  Failed buildings: {', '.join(failed)}")
        print()

    if total_on_disk >= 15:
        print("  STATUS: TARGET MET")
    else:
        print(f"  STATUS: BELOW TARGET ({total_on_disk}/15)")
        print("  Re-run this script to retry failed buildings.")

    # List all files on disk
    print("\n--- Files on disk ---")
    for glb in sorted(OUTPUT_DIR.glob("*.glb")):
        size_kb = glb.stat().st_size / 1024
        print(f"  {glb.name}: {size_kb:.0f} KB")


if __name__ == "__main__":
    main()
