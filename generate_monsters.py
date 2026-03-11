#!/usr/bin/env python3
"""Monster generation pipeline for Liminal horror game.

Multi-step pipeline: Generate base model (Meshy text-to-3D) -> Rig (Meshy rigging API)
-> Animate (Meshy animation API) -> Download final GLB.

Generates three monsters sharing visual DNA (pale grey skin, dark veiny texture):
  - Stalker: Tall humanoid hunter with elongated limbs
  - Lurker: Dark shadowy silhouette (rigging may fail -> Tripo fallback)
  - Ambusher: Ceiling crawler with spider-like proportions

Usage:
    python3 generate_monsters.py                  # Generate all three monsters
    python3 generate_monsters.py --monster stalker # Generate one monster
    python3 generate_monsters.py --force           # Regenerate everything
    python3 generate_monsters.py --help            # Show help
"""

import argparse
import json
import os
import sys
import time
import urllib.request
import urllib.error
from pathlib import Path

# ============================================================
# Configuration
# ============================================================

# Load .env
env = {}
env_path = Path(__file__).parent / ".env"
if env_path.exists():
    with open(env_path) as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                env[k] = v

MESHY_KEY = env.get("MESHY_API_KEY", "")
TRIPO_KEY = env.get("TRIPO_API_KEY", "")

BASE_DIR = Path(__file__).parent / "assets"
CHARACTERS_DIR = BASE_DIR / "models" / "characters"
TASKS_FILE = CHARACTERS_DIR / "monster_tasks.json"

# Shared visual DNA keywords for consistency across all three monsters
SHARED_DNA = "pale grey skin, dark veiny texture, horror creature, tattered remnants"
NEGATIVE_PROMPT = "cartoon, anime, bright, colorful, cute, high detail, photorealistic, cute, chibi"

# Monster definitions
MONSTERS = {
    "stalker": {
        "prompt": (
            "Grotesque tall humanoid horror monster, elongated limbs, "
            "pale grey skin, eyeless face with wide mouth of sharp teeth, "
            "hunched posture, tattered dark clothing remnants, dark veiny texture, "
            "bipedal, A-pose for rigging, game character"
        ),
        "height_meters": 2.2,
        "animations": ["idle", "walk", "attack"],
        "output_file": "stalker_monster.glb",
    },
    "lurker": {
        "prompt": (
            "Dark shadowy humanoid silhouette horror creature, pale grey skin "
            "visible through translucent darkness, vague limb shapes, formless "
            "dark entity, dark veiny texture, bipedal stance with hunched posture, "
            "A-pose for rigging, game character"
        ),
        "height_meters": 1.6,
        "animations": ["idle", "walk"],
        "output_file": "lurker_monster.glb",
    },
    "ambusher": {
        "prompt": (
            "Elongated horror creature with extra-long limbs for ceiling crawling, "
            "pale grey skin, dark veiny texture, spider-like proportions, sharp claws "
            "on hands and feet, tattered remnants, bipedal humanoid base, "
            "A-pose for rigging, game character"
        ),
        "height_meters": 1.8,
        "animations": ["idle", "walk", "attack"],
        "output_file": "ambusher_monster.glb",
    },
}

# ============================================================
# HTTP helpers (same pattern as generate_assets.py)
# ============================================================


def api_request(url, data=None, headers=None, method=None, timeout=120):
    """Make an API request and return parsed JSON or binary response."""
    if headers is None:
        headers = {}
    if data is not None and isinstance(data, dict):
        data = json.dumps(data).encode()
        headers.setdefault("Content-Type", "application/json")
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            content_type = resp.headers.get("Content-Type", "")
            body = resp.read()
            if "json" in content_type:
                return json.loads(body)
            return body
    except urllib.error.HTTPError as e:
        error_body = e.read().decode()
        print(f"  HTTP {e.code}: {error_body[:500]}")
        return None
    except urllib.error.URLError as e:
        print(f"  URL Error: {e.reason}")
        return None


def download_file(url, path):
    """Download a file from URL to path."""
    path.parent.mkdir(parents=True, exist_ok=True)
    urllib.request.urlretrieve(url, str(path))
    size_kb = path.stat().st_size / 1024
    print(f"  Downloaded: {path.name} ({size_kb:.0f} KB)")
    return size_kb


# ============================================================
# Task tracking (idempotency / resume support)
# ============================================================


def load_tasks():
    """Load task tracking JSON for resume support."""
    if TASKS_FILE.exists():
        with open(TASKS_FILE) as f:
            return json.load(f)
    return {}


def save_tasks(tasks):
    """Save task tracking JSON."""
    TASKS_FILE.parent.mkdir(parents=True, exist_ok=True)
    with open(TASKS_FILE, "w") as f:
        json.dump(tasks, f, indent=2)


# ============================================================
# Phase A: Base Model Generation (Meshy text-to-3D)
# ============================================================


def create_meshy_task(prompt, target_poly=5000):
    """Submit a text-to-3D task to Meshy with Meshy-6 params."""
    resp = api_request(
        "https://api.meshy.ai/openapi/v2/text-to-3d",
        data={
            "mode": "preview",
            "prompt": prompt,
            "negative_prompt": NEGATIVE_PROMPT,
            "ai_model": "meshy-6",
            "target_polycount": target_poly,
            "topology": "triangle",
            "model_type": "lowpoly",
            "should_remesh": True,
        },
        headers={"Authorization": f"Bearer {MESHY_KEY}"},
    )
    if resp and "result" in resp:
        return resp["result"]
    print(f"  Failed to create Meshy task: {resp}")
    return None


def poll_meshy_task(task_id, timeout=600):
    """Poll a Meshy text-to-3D task until completion."""
    start = time.time()
    while time.time() - start < timeout:
        resp = api_request(
            f"https://api.meshy.ai/openapi/v2/text-to-3d/{task_id}",
            headers={"Authorization": f"Bearer {MESHY_KEY}"},
            method="GET",
        )
        if not resp:
            time.sleep(10)
            continue
        status = resp.get("status", "UNKNOWN")
        progress = resp.get("progress", 0)
        if status == "SUCCEEDED":
            return resp
        elif status in ("FAILED", "CANCELED"):
            print(f"  Task {task_id}: {status}")
            return None
        print(f"    {task_id[:8]}... {status} {progress}%")
        time.sleep(15)
    print(f"  Task {task_id}: TIMEOUT after {timeout}s")
    return None


def generate_base_model(monster_name, monster_config, tasks):
    """Generate the base 3D model for a monster.

    Returns the GLB URL on success, None on failure.
    """
    print(f"\n  [Phase A] Generating base model for {monster_name}...")

    # Check if we already have a generation result
    monster_tasks = tasks.get(monster_name, {})
    if "generation_result" in monster_tasks:
        glb_url = monster_tasks["generation_result"].get("glb_url")
        if glb_url:
            print(f"  Resuming from previous generation (task: {monster_tasks.get('generation_task_id', 'unknown')[:8]}...)")
            return glb_url

    # Submit generation task
    task_id = create_meshy_task(monster_config["prompt"], target_poly=5000)
    if not task_id:
        # Retry once with 30s delay
        print(f"  Retrying generation in 30s...")
        time.sleep(30)
        task_id = create_meshy_task(monster_config["prompt"], target_poly=5000)
        if not task_id:
            print(f"  FAILED: Could not create generation task for {monster_name}")
            tasks.setdefault(monster_name, {})["generation_status"] = "FAILED"
            save_tasks(tasks)
            return None

    print(f"  Generation task: {task_id}")
    tasks.setdefault(monster_name, {})["generation_task_id"] = task_id
    save_tasks(tasks)

    # Poll for completion
    result = poll_meshy_task(task_id, timeout=600)
    if not result or "model_urls" not in result:
        print(f"  FAILED: Generation did not produce model URLs for {monster_name}")
        tasks[monster_name]["generation_status"] = "FAILED"
        save_tasks(tasks)
        return None

    glb_url = result["model_urls"].get("glb")
    if not glb_url:
        print(f"  FAILED: No GLB URL in generation result for {monster_name}")
        tasks[monster_name]["generation_status"] = "FAILED"
        save_tasks(tasks)
        return None

    tasks[monster_name]["generation_status"] = "SUCCEEDED"
    tasks[monster_name]["generation_result"] = {
        "glb_url": glb_url,
        "model_urls": result.get("model_urls", {}),
    }
    save_tasks(tasks)
    print(f"  Base model generated: {glb_url[:60]}...")
    return glb_url


# ============================================================
# Phase B: Rigging (Meshy rigging API)
# ============================================================


def poll_rigging_task(task_id, timeout=300):
    """Poll a Meshy rigging task until completion."""
    start = time.time()
    while time.time() - start < timeout:
        resp = api_request(
            f"https://api.meshy.ai/openapi/v1/rigging/{task_id}",
            headers={"Authorization": f"Bearer {MESHY_KEY}"},
            method="GET",
        )
        if not resp:
            time.sleep(10)
            continue
        status = resp.get("status", "UNKNOWN")
        progress = resp.get("progress", 0)
        if status == "SUCCEEDED":
            return resp
        elif status in ("FAILED", "CANCELED"):
            print(f"  Rigging task {task_id}: {status}")
            return None
        print(f"    Rigging {task_id[:8]}... {status} {progress}%")
        time.sleep(15)
    print(f"  Rigging task {task_id}: TIMEOUT after {timeout}s")
    return None


def rig_model_meshy(glb_url, height_meters, monster_name, tasks):
    """Rig a model via Meshy rigging API.

    Returns (rig_task_id, rigged_glb_url) on success, (None, None) on failure.
    """
    print(f"\n  [Phase B] Rigging {monster_name} via Meshy...")

    # Check if we already have a rigging result
    monster_tasks = tasks.get(monster_name, {})
    if "rigging_result" in monster_tasks:
        rig_task_id = monster_tasks.get("rigging_task_id")
        rigged_url = monster_tasks["rigging_result"].get("rigged_glb_url")
        if rig_task_id and rigged_url:
            print(f"  Resuming from previous rigging (task: {rig_task_id[:8]}...)")
            return rig_task_id, rigged_url

    # Submit rigging task
    resp = api_request(
        "https://api.meshy.ai/openapi/v1/rigging",
        data={
            "model_url": glb_url,
            "height_meters": height_meters,
        },
        headers={"Authorization": f"Bearer {MESHY_KEY}"},
    )
    if not resp or "result" not in resp:
        print(f"  Failed to create rigging task: {resp}")
        return None, None

    rig_task_id = resp["result"]
    print(f"  Rigging task: {rig_task_id}")
    tasks.setdefault(monster_name, {})["rigging_task_id"] = rig_task_id
    save_tasks(tasks)

    # Poll for completion
    result = poll_rigging_task(rig_task_id, timeout=300)
    if not result:
        print(f"  Meshy rigging FAILED for {monster_name}")
        tasks[monster_name]["rigging_status"] = "FAILED"
        save_tasks(tasks)
        return None, None

    rigged_url = result.get("rigged_character_glb_url")
    if not rigged_url:
        # Try alternative field names
        rigged_url = (
            result.get("model_urls", {}).get("glb")
            or result.get("output", {}).get("model")
        )

    if not rigged_url:
        print(f"  Rigging succeeded but no rigged GLB URL found for {monster_name}")
        tasks[monster_name]["rigging_status"] = "SUCCEEDED_NO_URL"
        save_tasks(tasks)
        return None, None

    tasks[monster_name]["rigging_status"] = "SUCCEEDED"
    tasks[monster_name]["rigging_result"] = {
        "rigged_glb_url": rigged_url,
    }
    save_tasks(tasks)
    print(f"  Rigged model URL: {rigged_url[:60]}...")
    return rig_task_id, rigged_url


def rig_model_tripo(prompt, monster_name, tasks):
    """Fallback: Generate + rig via Tripo API (for Lurker).

    Returns (rig_task_id, rigged_glb_url) on success, (None, None) on failure.
    """
    print(f"\n  [Phase B Fallback] Generating + rigging {monster_name} via Tripo...")

    if not TRIPO_KEY:
        print(f"  TRIPO_API_KEY not set, skipping Tripo fallback")
        return None, None

    # Check if we already have a Tripo result
    monster_tasks = tasks.get(monster_name, {})
    if "tripo_result" in monster_tasks:
        rigged_url = monster_tasks["tripo_result"].get("rigged_glb_url")
        if rigged_url:
            print(f"  Resuming from previous Tripo result")
            return monster_tasks.get("tripo_rig_task_id"), rigged_url

    # Step 1: Generate model via Tripo
    resp = api_request(
        "https://api.tripo3d.ai/v2/openapi/task",
        data={
            "type": "text_to_model",
            "prompt": prompt,
            "negative_prompt": NEGATIVE_PROMPT,
        },
        headers={"Authorization": f"Bearer {TRIPO_KEY}"},
    )
    if not resp or "data" not in resp:
        print(f"  Tripo generation failed: {resp}")
        return None, None

    gen_task_id = resp["data"]["task_id"]
    print(f"  Tripo generation task: {gen_task_id}")
    tasks.setdefault(monster_name, {})["tripo_gen_task_id"] = gen_task_id
    save_tasks(tasks)

    # Poll Tripo generation
    start = time.time()
    while time.time() - start < 600:
        resp = api_request(
            f"https://api.tripo3d.ai/v2/openapi/task/{gen_task_id}",
            headers={"Authorization": f"Bearer {TRIPO_KEY}"},
            method="GET",
        )
        if not resp:
            time.sleep(15)
            continue
        status = resp.get("data", {}).get("status", "UNKNOWN")
        progress = resp.get("data", {}).get("progress", 0)
        if status == "success":
            break
        elif status in ("failed", "cancelled"):
            print(f"  Tripo generation {status} for {monster_name}")
            tasks[monster_name]["tripo_status"] = "FAILED_GENERATION"
            save_tasks(tasks)
            return None, None
        print(f"    Tripo gen {gen_task_id[:8]}... {status} {progress}%")
        time.sleep(15)
    else:
        print(f"  Tripo generation TIMEOUT for {monster_name}")
        return None, None

    # Step 2: Rig via Tripo
    rig_resp = api_request(
        "https://api.tripo3d.ai/v2/openapi/task",
        data={
            "type": "animate_rig",
            "original_model_task_id": gen_task_id,
            "spec": "tripo",
        },
        headers={"Authorization": f"Bearer {TRIPO_KEY}"},
    )
    if not rig_resp or "data" not in rig_resp:
        print(f"  Tripo rigging submission failed: {rig_resp}")
        tasks[monster_name]["tripo_status"] = "FAILED_RIGGING"
        save_tasks(tasks)
        return None, None

    rig_task_id = rig_resp["data"]["task_id"]
    print(f"  Tripo rig task: {rig_task_id}")
    tasks[monster_name]["tripo_rig_task_id"] = rig_task_id
    save_tasks(tasks)

    # Poll Tripo rigging
    start = time.time()
    while time.time() - start < 300:
        resp = api_request(
            f"https://api.tripo3d.ai/v2/openapi/task/{rig_task_id}",
            headers={"Authorization": f"Bearer {TRIPO_KEY}"},
            method="GET",
        )
        if not resp:
            time.sleep(15)
            continue
        status = resp.get("data", {}).get("status", "UNKNOWN")
        if status == "success":
            output = resp.get("data", {}).get("output", {})
            rigged_url = output.get("model")
            if rigged_url:
                tasks[monster_name]["tripo_status"] = "SUCCEEDED"
                tasks[monster_name]["tripo_result"] = {"rigged_glb_url": rigged_url}
                save_tasks(tasks)
                print(f"  Tripo rigged model: {rigged_url[:60]}...")
                return rig_task_id, rigged_url
            break
        elif status in ("failed", "cancelled"):
            print(f"  Tripo rigging {status} for {monster_name}")
            tasks[monster_name]["tripo_status"] = "FAILED_RIGGING"
            save_tasks(tasks)
            return None, None
        print(f"    Tripo rig {rig_task_id[:8]}... {status}")
        time.sleep(15)

    print(f"  Tripo rigging did not produce a model URL for {monster_name}")
    return None, None


def rig_monster(glb_url, monster_name, monster_config, tasks):
    """Rig a monster, with Tripo fallback for Lurker.

    Returns (rig_task_id, rigged_glb_url) on success.
    For non-Lurker failures, retries once.
    """
    height = monster_config["height_meters"]

    # Attempt 1: Meshy rigging
    rig_task_id, rigged_url = rig_model_meshy(glb_url, height, monster_name, tasks)
    if rigged_url:
        return rig_task_id, rigged_url

    # Lurker fallback: try Tripo
    if monster_name == "lurker":
        print(f"  Meshy rigging failed for Lurker, trying Tripo fallback...")
        rig_task_id, rigged_url = rig_model_tripo(
            monster_config["prompt"], monster_name, tasks
        )
        if rigged_url:
            return rig_task_id, rigged_url
        # Both failed -- Lurker will use shader animation in Phase 7
        print(f"  Both Meshy and Tripo rigging failed for Lurker.")
        print(f"  Lurker will use unrigged mesh with shader-based animation (Phase 7).")
        tasks[monster_name]["rigging_final_status"] = "UNRIGGED_SHADER_FALLBACK"
        save_tasks(tasks)
        return None, None

    # Non-Lurker: retry Meshy once
    print(f"  Retrying Meshy rigging for {monster_name}...")
    # Clear previous rigging state to force re-attempt
    if monster_name in tasks:
        tasks[monster_name].pop("rigging_task_id", None)
        tasks[monster_name].pop("rigging_result", None)
        tasks[monster_name].pop("rigging_status", None)
        save_tasks(tasks)

    rig_task_id, rigged_url = rig_model_meshy(glb_url, height, monster_name, tasks)
    if rigged_url:
        return rig_task_id, rigged_url

    print(f"  Rigging FAILED for {monster_name} after retry. Continuing without rig.")
    tasks[monster_name]["rigging_final_status"] = "FAILED_AFTER_RETRY"
    save_tasks(tasks)
    return None, None


# ============================================================
# Phase C: Animation (Meshy animation API)
# ============================================================


def poll_animation_task(task_id, timeout=180):
    """Poll a Meshy animation task until completion."""
    start = time.time()
    while time.time() - start < timeout:
        resp = api_request(
            f"https://api.meshy.ai/openapi/v1/animations/{task_id}",
            headers={"Authorization": f"Bearer {MESHY_KEY}"},
            method="GET",
        )
        if not resp:
            time.sleep(10)
            continue
        status = resp.get("status", "UNKNOWN")
        progress = resp.get("progress", 0)
        if status == "SUCCEEDED":
            return resp
        elif status in ("FAILED", "CANCELED"):
            print(f"  Animation task {task_id}: {status}")
            return None
        print(f"    Animation {task_id[:8]}... {status} {progress}%")
        time.sleep(10)
    print(f"  Animation task {task_id}: TIMEOUT after {timeout}s")
    return None


def discover_animations(rig_task_id):
    """Discover available animation presets from Meshy.

    Returns a dict mapping animation names to action_ids.
    """
    # Try listing available animations for this rig
    resp = api_request(
        "https://api.meshy.ai/openapi/v1/animations/presets",
        headers={"Authorization": f"Bearer {MESHY_KEY}"},
        method="GET",
    )

    available = {}
    if resp and isinstance(resp, dict):
        presets = resp.get("results", resp.get("data", []))
        if isinstance(presets, list):
            for preset in presets:
                name = preset.get("name", "").lower()
                action_id = preset.get("id") or preset.get("action_id")
                if action_id:
                    available[name] = action_id

    # If we could not discover, use common action_id patterns
    if not available:
        print("  Could not discover animation presets, using default action_ids")
        available = {
            "idle": "idle",
            "walk": "walk",
            "run": "run",
            "attack": "attack",
        }

    return available


def animate_monster(rig_task_id, monster_name, monster_config, tasks):
    """Apply animations to a rigged monster.

    Returns the URL of the final animated GLB, or None.
    """
    needed_animations = monster_config["animations"]
    print(f"\n  [Phase C] Animating {monster_name}: {', '.join(needed_animations)}...")

    # Check if we already have animation results
    monster_tasks = tasks.get(monster_name, {})
    if "animation_results" in monster_tasks:
        existing = monster_tasks["animation_results"]
        if all(a in existing for a in needed_animations):
            # Find the last animation's GLB URL
            last_anim = needed_animations[-1]
            last_url = existing[last_anim].get("glb_url")
            if last_url:
                print(f"  Resuming from previous animations")
                return last_url

    # Discover available animation presets
    available = discover_animations(rig_task_id)
    print(f"  Available animations: {list(available.keys())[:10]}...")

    animation_results = monster_tasks.get("animation_results", {})
    final_glb_url = None

    for anim_name in needed_animations:
        if anim_name in animation_results and animation_results[anim_name].get("glb_url"):
            print(f"  Skipping {anim_name} (already done)")
            final_glb_url = animation_results[anim_name]["glb_url"]
            continue

        # Find the best matching action_id
        action_id = available.get(anim_name)
        if not action_id:
            # Try partial matches
            for key, val in available.items():
                if anim_name in key or key in anim_name:
                    action_id = val
                    break
        if not action_id:
            action_id = anim_name  # Use name directly as fallback

        print(f"  Applying animation: {anim_name} (action_id: {action_id})")

        resp = api_request(
            "https://api.meshy.ai/openapi/v1/animations",
            data={
                "rig_task_id": rig_task_id,
                "action_id": action_id,
                "change_fps": 30,
            },
            headers={"Authorization": f"Bearer {MESHY_KEY}"},
        )

        if not resp or "result" not in resp:
            print(f"  FAILED to submit animation '{anim_name}': {resp}")
            animation_results[anim_name] = {"status": "SUBMIT_FAILED"}
            continue

        anim_task_id = resp["result"]
        print(f"  Animation task: {anim_task_id}")

        result = poll_animation_task(anim_task_id, timeout=180)
        if not result:
            print(f"  Animation '{anim_name}' FAILED for {monster_name}, skipping")
            animation_results[anim_name] = {
                "status": "FAILED",
                "task_id": anim_task_id,
            }
        else:
            glb_url = (
                result.get("animated_glb_url")
                or result.get("model_urls", {}).get("glb")
                or result.get("output", {}).get("model")
            )
            animation_results[anim_name] = {
                "status": "SUCCEEDED",
                "task_id": anim_task_id,
                "glb_url": glb_url,
            }
            if glb_url:
                final_glb_url = glb_url
                print(f"  Animation '{anim_name}' succeeded")
            else:
                print(f"  Animation '{anim_name}' succeeded but no GLB URL found")

        # Save progress after each animation
        tasks.setdefault(monster_name, {})["animation_results"] = animation_results
        save_tasks(tasks)
        time.sleep(2)  # Rate limit courtesy

    return final_glb_url


# ============================================================
# Main pipeline
# ============================================================


def should_skip_monster(monster_name, force=False):
    """Check if a monster should be skipped (already complete).

    A monster is considered complete if its GLB exists and is > 500KB
    (indicating mesh + rig + animation data).
    """
    if force:
        return False

    output_path = CHARACTERS_DIR / MONSTERS[monster_name]["output_file"]
    if output_path.exists() and output_path.stat().st_size > 500 * 1024:
        print(f"\n  Skipping {monster_name} (GLB exists and > 500KB)")
        return True
    return False


def process_monster(monster_name, force=False):
    """Run the full pipeline for a single monster: generate -> rig -> animate -> download.

    Returns True if the final GLB file was produced, False otherwise.
    """
    monster_config = MONSTERS[monster_name]
    output_path = CHARACTERS_DIR / monster_config["output_file"]

    print(f"\n{'='*50}")
    print(f"Processing: {monster_name.upper()}")
    print(f"{'='*50}")

    # Check idempotency
    if should_skip_monster(monster_name, force):
        return True

    # Load task tracking
    tasks = load_tasks()

    # Phase A: Generate base model
    glb_url = generate_base_model(monster_name, monster_config, tasks)
    if not glb_url:
        print(f"\n  RESULT: {monster_name} generation FAILED")
        return False

    # Phase B: Rig the model
    rig_task_id, rigged_url = rig_monster(glb_url, monster_name, monster_config, tasks)

    # Phase C: Animate (only if rigged)
    final_url = None
    if rig_task_id and rigged_url:
        final_url = animate_monster(rig_task_id, monster_name, monster_config, tasks)

    # Download the best available GLB
    # Priority: animated GLB > rigged GLB > base GLB
    download_url = final_url or rigged_url or glb_url

    if download_url:
        # Back up existing file if present
        if output_path.exists():
            backup_name = output_path.stem + "_old" + output_path.suffix
            backup_path = output_path.parent / backup_name
            print(f"\n  Backing up existing {output_path.name} -> {backup_name}")
            os.rename(str(output_path), str(backup_path))

        print(f"\n  Downloading final GLB for {monster_name}...")
        size_kb = download_file(download_url, output_path)

        # Record final status
        tasks = load_tasks()
        tasks.setdefault(monster_name, {})["final_status"] = {
            "has_rig": rig_task_id is not None,
            "has_animations": final_url is not None,
            "file_size_kb": round(size_kb, 1),
            "source": (
                "animated" if final_url
                else "rigged" if rigged_url
                else "base_mesh"
            ),
        }
        save_tasks(tasks)

        print(f"\n  RESULT: {monster_name} complete ({size_kb:.0f}KB, "
              f"{'rigged+animated' if final_url else 'rigged' if rigged_url else 'base mesh only'})")
        return True
    else:
        print(f"\n  RESULT: {monster_name} - no downloadable model produced")
        return False


def main():
    parser = argparse.ArgumentParser(
        description="Generate monster models with rigging and animations for Liminal horror game"
    )
    parser.add_argument(
        "--monster",
        choices=list(MONSTERS.keys()),
        help="Process a single monster (default: all three)",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Regenerate even if GLB already exists and is > 500KB",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Show what would be generated without calling APIs",
    )
    args = parser.parse_args()

    if not MESHY_KEY:
        print("ERROR: MESHY_API_KEY not found in .env file")
        sys.exit(1)

    print("=" * 60)
    print("LIMINAL MONSTER GENERATION PIPELINE")
    print("=" * 60)
    print(f"Meshy API key: {MESHY_KEY[:8]}...{MESHY_KEY[-4:]}")
    print(f"Tripo API key: {'set' if TRIPO_KEY else 'NOT SET (Lurker fallback unavailable)'}")
    print(f"Output dir: {CHARACTERS_DIR}")

    # Determine which monsters to process
    if args.monster:
        monster_list = [args.monster]
    else:
        monster_list = list(MONSTERS.keys())

    if args.dry_run:
        print("\n  DRY RUN -- would process:")
        for name in monster_list:
            config = MONSTERS[name]
            skip = should_skip_monster(name, args.force)
            status = "SKIP (exists)" if skip else "WOULD GENERATE"
            print(f"    {name}: {status}")
            print(f"      Prompt: {config['prompt'][:80]}...")
            print(f"      Height: {config['height_meters']}m")
            print(f"      Animations: {', '.join(config['animations'])}")
        return 0

    CHARACTERS_DIR.mkdir(parents=True, exist_ok=True)

    # Process monsters
    results = {}
    for name in monster_list:
        success = process_monster(name, force=args.force)
        results[name] = success

    # Summary
    print(f"\n{'='*60}")
    print("MONSTER GENERATION SUMMARY")
    print(f"{'='*60}")

    tasks = load_tasks()
    for name, success in results.items():
        output_path = CHARACTERS_DIR / MONSTERS[name]["output_file"]
        if output_path.exists():
            size_kb = output_path.stat().st_size / 1024
            final = tasks.get(name, {}).get("final_status", {})
            source = final.get("source", "unknown")
            print(f"  {name}: {'OK' if success else 'PARTIAL'} ({size_kb:.0f}KB, {source})")
        else:
            print(f"  {name}: FAILED (no file)")

    failed = [n for n, s in results.items() if not s]
    if failed:
        print(f"\n  WARNING: Failed monsters: {', '.join(failed)}")
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
