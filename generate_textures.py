#!/usr/bin/env python3
"""PBR texture generation script via Scenario API.

Generates complete PBR texture sets (albedo, normal, roughness) for all
surface types using the Scenario txt2img-texture API. Replaces placeholder
normal/roughness maps and adds new texture types.

Usage:
    python3 generate_textures.py             # Generate missing/placeholder textures
    python3 generate_textures.py --force     # Regenerate everything
    python3 generate_textures.py --dry-run   # Show what would be generated
"""

import argparse
import base64
import json
import os
import shutil
import sys
import time
import urllib.request
import urllib.error
from pathlib import Path

# ============================================================
# Configuration
# ============================================================

BASE_DIR = Path(__file__).parent / "assets" / "textures"
ENV_PATH = Path(__file__).parent / ".env"

# Placeholder detection: files under this size are placeholders
PLACEHOLDER_THRESHOLD = 2000  # bytes

# Scenario API settings
SCENARIO_API_URL = "https://api.cloud.scenario.com/v1/generate/txt2img-texture"
TEXTURE_WIDTH = 256
TEXTURE_HEIGHT = 256
NUM_INFERENCE_STEPS = 30
GUIDANCE = 7.5

# Shared negative prompt for warm decay palette
NEGATIVE_PROMPT = "clean, new, bright, cartoon, anime, polished, pristine, modern"

# Maps we care about from Scenario response
PBR_MAP_TYPES = ["albedo", "normal", "roughness"]

# ============================================================
# Texture inventory
# ============================================================

TEXTURES = [
    # Floors
    {
        "name": "asphalt",
        "category": "floors",
        "prompt": "Cracked asphalt road surface, grey with oil stains, weeds growing through cracks, weathered, abandoned, seamless tileable texture",
        "regenerate_albedo": False,
    },
    {
        "name": "grass",
        "category": "floors",
        "prompt": "Overgrown grass patches with dirt showing through, dried yellow-green, unkempt, abandoned yard, weathered, seamless tileable texture",
        "regenerate_albedo": False,
    },
    {
        "name": "wood",
        "category": "floors",
        "prompt": "Old wooden floorboards, warped and stained, dark brown wood grain, gaps between planks, weathered, abandoned building, seamless tileable texture",
        "regenerate_albedo": False,
    },
    {
        "name": "dirt",
        "category": "floors",
        "prompt": "Packed dirt ground with small stones and debris, brown earth, dry and dusty, tire tracks, abandoned lot, seamless tileable texture",
        "regenerate_albedo": True,
    },
    {
        "name": "tile",
        "category": "floors",
        "prompt": "Cracked linoleum floor tiles, 1970s pattern faded, stained, dirty grout lines, abandoned building interior, seamless tileable texture",
        "regenerate_albedo": True,
    },
    # Walls
    {
        "name": "brick",
        "category": "walls",
        "prompt": "Old red brick wall, crumbling mortar, moss in crevices, stained, weathered, abandoned building, seamless tileable texture",
        "regenerate_albedo": False,
    },
    {
        "name": "concrete",
        "category": "walls",
        "prompt": "Cracked concrete wall surface, grey with rust stains, moss in crevices, water damage, weathered, abandoned building, seamless tileable texture",
        "regenerate_albedo": False,
    },
    {
        "name": "wallpaper",
        "category": "walls",
        "prompt": "Peeling vintage wallpaper, floral pattern partially torn revealing plaster underneath, stained, water damage, abandoned interior, seamless tileable texture",
        "regenerate_albedo": True,
    },
    # Props/Materials
    {
        "name": "metal",
        "category": "props",
        "prompt": "Scratched industrial metal surface, dull grey steel, dents, weathered, abandoned factory, seamless tileable texture",
        "regenerate_albedo": False,
    },
    {
        "name": "rust",
        "category": "props",
        "prompt": "Heavy rust on metal surface, orange-brown corrosion, flaking paint, industrial decay, abandoned, seamless tileable texture",
        "regenerate_albedo": False,
    },
    {
        "name": "dark",
        "category": "props",
        "prompt": "Dark stained surface, almost black with subtle brown undertones, grimy, soot-covered, abandoned horror, seamless tileable texture",
        "regenerate_albedo": False,
    },
    {
        "name": "roof_shingles",
        "category": "props",
        "prompt": "Old asphalt roof shingles, curling edges, dark grey with moss patches, missing shingles revealing tar paper, weathered, abandoned, seamless tileable texture",
        "regenerate_albedo": True,
    },
]


# ============================================================
# Environment / Auth
# ============================================================

def load_env():
    """Load environment variables from .env file."""
    env = {}
    if not ENV_PATH.exists():
        print(f"ERROR: .env file not found at {ENV_PATH}")
        sys.exit(1)
    with open(ENV_PATH) as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                env[k] = v
    return env


def get_auth_header(env):
    """Build Basic auth header for Scenario API."""
    api_key = env.get("SCENARIO_API_KEY", "").strip()
    secret_key = env.get("SCENARIO_SECRET_KEY", "").strip()
    if not api_key or not secret_key:
        print("ERROR: SCENARIO_API_KEY and SCENARIO_SECRET_KEY must be set in .env")
        sys.exit(1)
    credentials = f"{api_key}:{secret_key}"
    encoded = base64.b64encode(credentials.encode()).decode()
    return f"Basic {encoded}"


# ============================================================
# HTTP helpers
# ============================================================

def api_request(url, data=None, headers=None, method=None):
    """Make an API request and return parsed JSON."""
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
    except urllib.error.URLError as e:
        print(f"  URL Error: {e.reason}")
        return None
    except Exception as e:
        print(f"  Request error: {e}")
        return None


def download_file(url, path):
    """Download a file from URL to path."""
    path.parent.mkdir(parents=True, exist_ok=True)
    try:
        urllib.request.urlretrieve(url, str(path))
        size_bytes = path.stat().st_size
        print(f"    Downloaded: {path.name} ({size_bytes} bytes)")
        return True
    except Exception as e:
        print(f"    Download failed for {path.name}: {e}")
        return False


# ============================================================
# Placeholder detection
# ============================================================

def is_placeholder(file_path):
    """Check if a texture file is a placeholder (< PLACEHOLDER_THRESHOLD bytes)."""
    if not file_path.exists():
        return True  # Missing is treated as needing generation
    return file_path.stat().st_size < PLACEHOLDER_THRESHOLD


def needs_generation(texture, force=False):
    """Determine which map types need generation for a texture.

    Returns a list of map types that need to be generated.
    """
    needed = []
    category_dir = BASE_DIR / texture["category"]

    for map_type in PBR_MAP_TYPES:
        file_path = category_dir / f"{texture['name']}_{map_type}.png"

        if force:
            needed.append(map_type)
            continue

        # For existing textures where albedo is OK, skip albedo
        if map_type == "albedo" and not texture["regenerate_albedo"]:
            if file_path.exists() and not is_placeholder(file_path):
                continue

        # Check if file exists and is not a placeholder
        if is_placeholder(file_path):
            needed.append(map_type)

    return needed


# ============================================================
# Scenario API interaction
# ============================================================

def submit_generation(prompt, auth_header):
    """Submit a texture generation request to Scenario API.

    Returns the generation/inference ID for polling.
    """
    data = {
        "prompt": prompt,
        "negativePrompt": NEGATIVE_PROMPT,
        "width": TEXTURE_WIDTH,
        "height": TEXTURE_HEIGHT,
        "numOutputs": 1,
        "numInferenceSteps": NUM_INFERENCE_STEPS,
        "guidance": GUIDANCE,
    }

    resp = api_request(
        SCENARIO_API_URL,
        data=data,
        headers={
            "Authorization": auth_header,
            "Content-Type": "application/json",
        },
    )

    if not resp:
        return None

    # Scenario API returns an inference object with an ID
    inference = resp.get("inference", resp)
    inference_id = inference.get("id") or inference.get("inferenceId")

    if not inference_id:
        # Try alternate response structures
        if isinstance(resp, dict):
            inference_id = resp.get("id") or resp.get("inferenceId")
            if not inference_id and "data" in resp:
                inference_id = resp["data"].get("id") or resp["data"].get("inferenceId")

    if inference_id:
        print(f"    Submitted: inference {inference_id}")
        return inference_id

    print(f"    Unexpected response structure: {json.dumps(resp)[:300]}")
    return None


def poll_generation(inference_id, auth_header, timeout=300):
    """Poll Scenario API for generation completion.

    Returns the inference result with asset URLs when complete.
    """
    poll_url = f"https://api.cloud.scenario.com/v1/generate/txt2img-texture/{inference_id}"
    start = time.time()

    while time.time() - start < timeout:
        resp = api_request(
            poll_url,
            headers={"Authorization": auth_header},
            method="GET",
        )

        if not resp:
            time.sleep(10)
            continue

        inference = resp.get("inference", resp)
        status = inference.get("status", "unknown")

        if status in ("succeeded", "complete", "SUCCEEDED", "COMPLETE"):
            return inference
        elif status in ("failed", "FAILED", "error", "ERROR"):
            print(f"    Generation FAILED: {inference.get('error', 'unknown error')}")
            return None
        else:
            progress = inference.get("progress", "?")
            print(f"    Status: {status} (progress: {progress})")

        time.sleep(10)

    print(f"    Generation TIMEOUT after {timeout}s")
    return None


def extract_map_urls(inference_result):
    """Extract PBR map download URLs from Scenario inference result.

    The Scenario txt2img-texture endpoint returns separate URLs for each
    PBR map type (albedo, normal, roughness, etc.).

    Returns a dict mapping map_type -> URL.
    """
    urls = {}

    # Try various response structures the API might use
    # Structure 1: inference.images[].type / inference.images[].url
    images = inference_result.get("images", [])
    if not images:
        images = inference_result.get("outputs", [])
    if not images:
        images = inference_result.get("assets", [])

    if images:
        for img in images:
            if isinstance(img, dict):
                # Map type might be in "type", "mapType", "name", or "label"
                map_type = (
                    img.get("type", "")
                    or img.get("mapType", "")
                    or img.get("name", "")
                    or img.get("label", "")
                ).lower()

                # Normalize map type names
                if "albedo" in map_type or "diffuse" in map_type or "color" in map_type or "base" in map_type:
                    url = img.get("url") or img.get("downloadUrl") or img.get("imageUrl")
                    if url:
                        urls["albedo"] = url
                elif "normal" in map_type:
                    url = img.get("url") or img.get("downloadUrl") or img.get("imageUrl")
                    if url:
                        urls["normal"] = url
                elif "roughness" in map_type:
                    url = img.get("url") or img.get("downloadUrl") or img.get("imageUrl")
                    if url:
                        urls["roughness"] = url

    # Structure 2: inference.maps.albedo / normal / roughness
    maps = inference_result.get("maps", {})
    if maps:
        for map_type in PBR_MAP_TYPES:
            if map_type in maps and maps[map_type]:
                map_data = maps[map_type]
                url = map_data if isinstance(map_data, str) else map_data.get("url", "")
                if url:
                    urls[map_type] = url

    # Structure 3: Direct URL fields
    for map_type in PBR_MAP_TYPES:
        key_variants = [
            f"{map_type}Url",
            f"{map_type}_url",
            f"{map_type}MapUrl",
        ]
        for key in key_variants:
            if key in inference_result and inference_result[key]:
                urls[map_type] = inference_result[key]

    return urls


# ============================================================
# Backup and save
# ============================================================

def backup_existing(file_path):
    """Backup an existing file before overwriting."""
    if file_path.exists() and file_path.stat().st_size > PLACEHOLDER_THRESHOLD:
        backup_path = file_path.with_name(
            file_path.stem + "_old" + file_path.suffix
        )
        if not backup_path.exists():
            shutil.copy2(file_path, backup_path)
            print(f"    Backed up: {file_path.name} -> {backup_path.name}")


# ============================================================
# Main generation logic
# ============================================================

def generate_texture(texture, auth_header, force=False, dry_run=False):
    """Generate PBR maps for a single texture type.

    Returns (success: bool, maps_generated: list[str], error: str|None)
    """
    name = texture["name"]
    category = texture["category"]
    category_dir = BASE_DIR / category
    category_dir.mkdir(parents=True, exist_ok=True)

    needed = needs_generation(texture, force=force)
    if not needed:
        print(f"  [{name}] All maps present and valid, skipping")
        return True, [], None

    print(f"  [{name}] Need to generate: {', '.join(needed)}")

    if dry_run:
        return True, needed, None

    # Submit generation request
    inference_id = submit_generation(texture["prompt"], auth_header)
    if not inference_id:
        return False, [], "Failed to submit generation request"

    # Poll for completion
    result = poll_generation(inference_id, auth_header)
    if not result:
        return False, [], "Generation failed or timed out"

    # Extract map URLs
    map_urls = extract_map_urls(result)
    if not map_urls:
        print(f"    WARNING: No map URLs found in response")
        print(f"    Response keys: {list(result.keys()) if isinstance(result, dict) else 'not a dict'}")
        return False, [], "No map URLs in response"

    # Download needed maps
    downloaded = []
    for map_type in needed:
        if map_type not in map_urls:
            print(f"    WARNING: No URL for {map_type} map")
            continue

        file_path = category_dir / f"{name}_{map_type}.png"

        # Backup existing non-placeholder files
        backup_existing(file_path)

        # Download
        if download_file(map_urls[map_type], file_path):
            # Verify download is not a placeholder
            if file_path.stat().st_size < PLACEHOLDER_THRESHOLD:
                print(f"    WARNING: Downloaded {map_type} map is suspiciously small ({file_path.stat().st_size} bytes)")
            else:
                downloaded.append(map_type)

    missing = [m for m in needed if m not in downloaded]
    if missing:
        return False, downloaded, f"Missing maps after generation: {', '.join(missing)}"

    return True, downloaded, None


def generate_all_textures(force=False, dry_run=False):
    """Generate PBR textures for all surface types.

    Returns summary statistics.
    """
    env = load_env()
    auth_header = get_auth_header(env)

    print("=" * 60)
    print("PBR TEXTURE GENERATION (Scenario API)")
    print("=" * 60)

    # Phase 1: Analyze what needs generation
    print("\n--- Analysis ---")
    total_maps_needed = 0
    for texture in TEXTURES:
        needed = needs_generation(texture, force=force)
        status = "OK" if not needed else f"NEED: {', '.join(needed)}"
        print(f"  {texture['category']}/{texture['name']}: {status}")
        total_maps_needed += len(needed)

    if total_maps_needed == 0 and not force:
        print("\nAll textures are present and valid. Use --force to regenerate.")
        return {"total": len(TEXTURES), "succeeded": len(TEXTURES), "failed": 0, "skipped": 0}

    print(f"\nTotal maps to generate: {total_maps_needed}")
    if dry_run:
        print("\n[DRY RUN] No API calls will be made.")

    # Phase 2: Generate textures
    print("\n--- Generation ---")
    succeeded = 0
    failed = 0
    skipped = 0
    failed_textures = []
    all_results = []

    for texture in TEXTURES:
        name = texture["name"]
        print(f"\n  Processing: {name}")

        success, maps, error = generate_texture(texture, auth_header, force=force, dry_run=dry_run)

        if success and not maps:
            skipped += 1
        elif success:
            succeeded += 1
        else:
            # First failure: retry once
            print(f"    RETRY: {name} (error: {error})")
            time.sleep(5)
            success, maps, error = generate_texture(texture, auth_header, force=force, dry_run=dry_run)
            if success:
                succeeded += 1
            else:
                failed += 1
                failed_textures.append((name, error))

        all_results.append({
            "name": name,
            "category": texture["category"],
            "success": success,
            "maps_generated": maps,
            "error": error,
        })

        # Rate limiting between API calls
        if not dry_run and maps:
            time.sleep(2)

    # Phase 3: Summary
    print("\n" + "=" * 60)
    print("GENERATION SUMMARY")
    print("=" * 60)
    print(f"  Total textures: {len(TEXTURES)}")
    print(f"  Succeeded: {succeeded}")
    print(f"  Skipped (already valid): {skipped}")
    print(f"  Failed: {failed}")

    if failed_textures:
        print("\n  Failed textures:")
        for name, error in failed_textures:
            print(f"    - {name}: {error}")

    # Verify final state
    print("\n--- Final Verification ---")
    all_valid = True
    for texture in TEXTURES:
        category_dir = BASE_DIR / texture["category"]
        for map_type in PBR_MAP_TYPES:
            file_path = category_dir / f"{texture['name']}_{map_type}.png"
            if not file_path.exists():
                print(f"  MISSING: {file_path.relative_to(BASE_DIR)}")
                all_valid = False
            elif is_placeholder(file_path):
                size = file_path.stat().st_size
                print(f"  PLACEHOLDER: {file_path.relative_to(BASE_DIR)} ({size} bytes)")
                all_valid = False
            else:
                size = file_path.stat().st_size
                print(f"  OK: {file_path.relative_to(BASE_DIR)} ({size} bytes)")

    if all_valid:
        print("\n  All textures validated successfully!")
    else:
        print("\n  WARNING: Some textures are missing or still placeholders.")

    return {
        "total": len(TEXTURES),
        "succeeded": succeeded,
        "failed": failed,
        "skipped": skipped,
        "all_valid": all_valid,
    }


# ============================================================
# CLI
# ============================================================

def main():
    parser = argparse.ArgumentParser(
        description="Generate PBR textures via Scenario API"
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Regenerate all textures even if they already exist",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Show what would be generated without making API calls",
    )
    args = parser.parse_args()

    result = generate_all_textures(force=args.force, dry_run=args.dry_run)

    if result["failed"] > 0:
        sys.exit(1)


if __name__ == "__main__":
    main()
