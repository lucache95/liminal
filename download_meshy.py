#!/usr/bin/env python3
"""Download all completed Meshy models in parallel."""

import json
import urllib.request
import time
from pathlib import Path

MESHY_KEY = "msy_ThlmbTQWbaK7FSNiKAtPIbX3SqVz4ztJXZPX"
BASE_DIR = Path(__file__).parent / "assets" / "models"

# All submitted task IDs with their target paths
TASKS = {
    "019cddca-8391-73c9-a972-6a354d2d0268": ("environment", "abandoned_house_01"),
    "019cddca-8834-7289-9ee0-7d92533b6ff3": ("environment", "abandoned_house_02"),
    "019cddca-8cd7-7289-b04d-c4f82db0192c": ("environment", "church"),
    "019cddca-9179-73cb-a195-7de4c0df51a1": ("environment", "gas_station"),
    "019cddca-960f-728b-b46c-5e00e5ca1e22": ("environment", "warehouse"),
    "019cddca-9aa1-73cc-b501-276a1e7569b6": ("environment", "general_store"),
    "019cddca-9f35-73cd-9626-314f6f371e8f": ("props", "wooden_barrel"),
    "019cddca-a3d9-728b-8204-c238ae001655": ("props", "dumpster"),
    "019cddca-abfe-7043-88e4-69152c7f48f3": ("props", "old_car"),
    "019cddca-b3c4-728b-94dd-d8b3a99cfa08": ("props", "rusty_gate"),
    "019cddca-c1f7-7936-85ee-34e50dcef4bd": ("props", "generator"),
    "019cddca-ca31-73d1-a1de-687bd8eb9915": ("props", "wooden_crate"),
    "019cddca-d241-7290-b226-c2db284c6521": ("props", "park_bench"),
    "019cddca-dfbf-7291-9c5a-952910981bfa": ("props", "street_lamp"),
    "019cddca-e8eb-793b-ba38-2245e44226a1": ("characters", "stalker_monster"),
}

def check_and_download(task_id, category, name):
    output_dir = BASE_DIR / category
    output_dir.mkdir(parents=True, exist_ok=True)
    output_path = output_dir / f"{name}.glb"

    if output_path.exists() and output_path.stat().st_size > 1000:
        print(f"  SKIP {name} (already downloaded)")
        return True

    req = urllib.request.Request(
        f"https://api.meshy.ai/openapi/v2/text-to-3d/{task_id}",
        headers={"Authorization": f"Bearer {MESHY_KEY}"},
    )
    with urllib.request.urlopen(req) as resp:
        data = json.loads(resp.read())

    status = data["status"]
    progress = data["progress"]

    if status == "SUCCEEDED":
        glb_url = data["model_urls"]["glb"]
        if glb_url:
            urllib.request.urlretrieve(glb_url, str(output_path))
            size_kb = output_path.stat().st_size / 1024
            print(f"  OK   {name} ({size_kb:.0f} KB)")
            return True
        else:
            print(f"  ERR  {name} - no GLB URL")
            return False
    elif status in ("FAILED", "CANCELED"):
        print(f"  FAIL {name}: {status}")
        return True  # don't retry
    else:
        print(f"  WAIT {name}: {status} {progress}%")
        return False

print("=== DOWNLOADING MESHY MODELS ===\n")

max_attempts = 40  # 40 * 15s = 10 minutes max wait
for attempt in range(max_attempts):
    pending = []
    for task_id, (category, name) in TASKS.items():
        if not check_and_download(task_id, category, name):
            pending.append(task_id)

    if not pending:
        print("\nAll models downloaded!")
        break

    print(f"\n  {len(pending)} models still generating, waiting 15s...\n")
    time.sleep(15)
else:
    print(f"\nTimeout - {len(pending)} models still pending")

# List all downloaded files
print("\n=== DOWNLOADED FILES ===")
for glb in sorted(BASE_DIR.rglob("*.glb")):
    size_kb = glb.stat().st_size / 1024
    print(f"  {glb.relative_to(BASE_DIR)}: {size_kb:.0f} KB")
