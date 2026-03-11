#!/usr/bin/env python3
"""Asset validation script for Liminal horror game.

Validates all generated 3D models (.glb) and textures (.png) against
quality and format requirements. Used by all Phase 1 plans to verify
assets meet specifications.

Usage:
    python3 validate_assets.py                          # Validate all categories
    python3 validate_assets.py --category buildings     # Buildings only
    python3 validate_assets.py --quick                  # File existence only
    python3 validate_assets.py --verbose                # Detailed per-asset info
    python3 validate_assets.py --category characters --check-rig  # Check rigging
"""

import argparse
import json
import struct
import sys
from pathlib import Path

BASE_DIR = Path(__file__).parent / "assets"

# ============================================================
# Expected assets per category
# ============================================================

EXPECTED_BUILDINGS = [
    "abandoned_house_01",
    "abandoned_house_02",
    "church",
    "gas_station",
    "warehouse",
    "general_store",
    "hardware_store",
    "diner",
    "bar_tavern",
    "house_ranch",
    "house_colonial",
    "motel",
    "school",
    "factory",
    "radio_station",
    "ranger_station",
    "pharmacy",
    "trailer_home",
]

EXPECTED_PROPS = [
    # Existing
    "street_lamp",
    "park_bench",
    "rusty_gate",
    "old_car",
    "wooden_barrel",
    "dumpster",
    "wooden_crate",
    "generator",
    # New street furniture
    "mailbox",
    "fire_hydrant",
    "phone_booth",
    "trash_can",
    # New barriers
    "traffic_cone",
    "road_barrier",
    "chain_link_fence",
    # New vehicles
    "pickup_truck",
    "police_car",
    # New debris/containers
    "tire_stack",
    # New interior
    "overturned_table",
    "broken_chair",
    "old_tv",
    "filing_cabinet",
    "torn_couch",
    "rusted_refrigerator",
    "fallen_bookshelf",
    # New vegetation
    "dead_tree",
    "overgrown_bushes",
]

EXPECTED_CHARACTERS = [
    "stalker_monster",
    "lurker_monster",
    "ambusher_monster",
]

# Texture surface types and their required maps
TEXTURE_SURFACES = {
    "floors": [
        "asphalt",
        "grass",
        "wood",
        "dirt",
        "tile",
    ],
    "walls": [
        "brick",
        "concrete",
        "wallpaper",
    ],
    "props": [
        "metal",
        "rust",
        "dark",
        "roof_shingles",
    ],
}

TEXTURE_MAP_TYPES = ["albedo", "normal", "roughness"]

# Size constraints (in KB)
SIZE_RANGES = {
    "buildings": (100, 5000),   # 100KB - 5MB
    "props": (50, 3000),        # 50KB - 3MB
    "characters": (100, 10000), # 100KB - 10MB
}

# Minimum asset counts
MIN_COUNTS = {
    "buildings": 15,
    "props": 20,
    "characters": 3,
}

# ============================================================
# Validation functions
# ============================================================


def validate_glb(path: Path, category: str, verbose: bool = False) -> dict:
    """Validate a GLB file for format, size, and integrity.

    Args:
        path: Path to .glb file
        category: One of 'buildings', 'props', 'characters'
        verbose: Print detailed information

    Returns:
        dict with 'valid', 'issues', 'size_kb', 'version' keys
    """
    result = {
        "name": path.stem,
        "path": str(path),
        "valid": True,
        "issues": [],
        "size_kb": 0,
        "version": None,
    }

    if not path.exists():
        result["valid"] = False
        result["issues"].append("File does not exist")
        return result

    size_bytes = path.stat().st_size
    size_kb = size_bytes / 1024
    result["size_kb"] = round(size_kb, 1)

    # Basic size check
    if size_bytes < 1024:
        result["valid"] = False
        result["issues"].append(f"File too small: {size_kb:.1f}KB (< 1KB)")
        return result

    # Read and validate GLB header
    try:
        with open(path, "rb") as f:
            header = f.read(12)
            if len(header) < 12:
                result["valid"] = False
                result["issues"].append("File too small to contain GLB header")
                return result

            magic = header[:4]
            if magic != b"glTF":
                result["valid"] = False
                result["issues"].append(
                    f"Invalid GLB magic number: {magic!r} (expected b'glTF')"
                )
                return result

            version = struct.unpack("<I", header[4:8])[0]
            total_length = struct.unpack("<I", header[8:12])[0]
            result["version"] = version

            if version != 2:
                result["valid"] = False
                result["issues"].append(f"Unexpected glTF version: {version} (expected 2)")

    except (OSError, struct.error) as e:
        result["valid"] = False
        result["issues"].append(f"Error reading file: {e}")
        return result

    # Category-specific size range check
    if category in SIZE_RANGES:
        min_kb, max_kb = SIZE_RANGES[category]
        if size_kb < min_kb:
            result["issues"].append(
                f"File smaller than expected for {category}: "
                f"{size_kb:.0f}KB (min {min_kb}KB)"
            )
        if size_kb > max_kb:
            result["issues"].append(
                f"File larger than expected for {category}: "
                f"{size_kb:.0f}KB (max {max_kb}KB)"
            )
        # Size warnings don't fail the asset, only magic/version/existence do

    if verbose:
        print(f"    Size: {size_kb:.1f}KB | Version: {version}")

    return result


def validate_glb_rigging(path: Path, verbose: bool = False) -> dict:
    """Check if a GLB file contains rigging and animation data.

    Parses the GLB JSON chunk to look for 'skins' (rigging) and
    'animations' (animation data) arrays.

    Args:
        path: Path to .glb file
        verbose: Print detailed information

    Returns:
        dict with 'has_skins', 'has_animations', 'skin_count', 'animation_count'
    """
    result = {
        "has_skins": False,
        "has_animations": False,
        "skin_count": 0,
        "animation_count": 0,
        "issues": [],
    }

    if not path.exists():
        result["issues"].append("File does not exist")
        return result

    try:
        with open(path, "rb") as f:
            # Read GLB header (12 bytes)
            header = f.read(12)
            if len(header) < 12 or header[:4] != b"glTF":
                result["issues"].append("Not a valid GLB file")
                return result

            # Read first chunk header (should be JSON)
            chunk_header = f.read(8)
            if len(chunk_header) < 8:
                result["issues"].append("Missing JSON chunk")
                return result

            chunk_length = struct.unpack("<I", chunk_header[:4])[0]
            chunk_type = struct.unpack("<I", chunk_header[4:8])[0]

            # 0x4E4F534A = "JSON" in little-endian
            if chunk_type != 0x4E4F534A:
                result["issues"].append("First chunk is not JSON")
                return result

            # Read and parse JSON chunk
            json_data = f.read(chunk_length)
            gltf = json.loads(json_data.decode("utf-8"))

            # Check for skins (rigging)
            skins = gltf.get("skins", [])
            result["has_skins"] = len(skins) > 0
            result["skin_count"] = len(skins)

            # Check for animations
            animations = gltf.get("animations", [])
            result["has_animations"] = len(animations) > 0
            result["animation_count"] = len(animations)

            if verbose:
                print(f"    Skins: {len(skins)} | Animations: {len(animations)}")
                if animations:
                    for anim in animations:
                        name = anim.get("name", "unnamed")
                        channels = len(anim.get("channels", []))
                        print(f"      Animation: {name} ({channels} channels)")

    except (OSError, json.JSONDecodeError, struct.error) as e:
        result["issues"].append(f"Error parsing GLB: {e}")

    return result


def validate_texture(path: Path, verbose: bool = False) -> dict:
    """Validate a PNG texture file.

    Checks:
    - Valid PNG header (8-byte magic number)
    - Dimensions between 128-256px (from IHDR chunk)
    - File size > 2KB (placeholder detection)

    Args:
        path: Path to .png file
        verbose: Print detailed information

    Returns:
        dict with 'valid', 'issues', 'width', 'height', 'size_bytes'
    """
    result = {
        "name": path.stem,
        "path": str(path),
        "valid": True,
        "issues": [],
        "width": None,
        "height": None,
        "size_bytes": 0,
    }

    if not path.exists():
        result["valid"] = False
        result["issues"].append("File does not exist")
        return result

    size_bytes = path.stat().st_size
    result["size_bytes"] = size_bytes

    # Placeholder detection
    if size_bytes < 2000:
        result["valid"] = False
        result["issues"].append(
            f"Likely placeholder: {size_bytes} bytes (< 2KB)"
        )

    try:
        with open(path, "rb") as f:
            # PNG magic number: 8 bytes
            png_sig = f.read(8)
            if png_sig != b"\x89PNG\r\n\x1a\n":
                result["valid"] = False
                result["issues"].append("Not a valid PNG file (bad magic number)")
                return result

            # IHDR chunk: 4 bytes length, 4 bytes type, then width + height
            chunk_len_data = f.read(4)
            chunk_type = f.read(4)

            if chunk_type != b"IHDR":
                result["valid"] = False
                result["issues"].append("First chunk is not IHDR")
                return result

            width = struct.unpack(">I", f.read(4))[0]
            height = struct.unpack(">I", f.read(4))[0]
            result["width"] = width
            result["height"] = height

            # Dimension checks (128-256px for PS1 aesthetic)
            if width < 128 or width > 256:
                result["issues"].append(
                    f"Width {width}px outside 128-256px range"
                )
            if height < 128 or height > 256:
                result["issues"].append(
                    f"Height {height}px outside 128-256px range"
                )

    except (OSError, struct.error) as e:
        result["valid"] = False
        result["issues"].append(f"Error reading file: {e}")

    if verbose and result["width"]:
        print(
            f"    Size: {size_bytes} bytes | "
            f"Dimensions: {result['width']}x{result['height']}"
        )

    return result


# ============================================================
# Category validators
# ============================================================


def validate_buildings(quick: bool = False, verbose: bool = False) -> tuple:
    """Validate building GLB assets.

    Returns:
        (passed, failed, total, results_list)
    """
    model_dir = BASE_DIR / "models" / "environment"
    results = []
    passed = 0
    failed = 0

    print("\n--- Buildings ---")
    print(f"Directory: {model_dir}")

    # Check all expected buildings
    for name in EXPECTED_BUILDINGS:
        path = model_dir / f"{name}.glb"

        if quick:
            exists = path.exists() and path.stat().st_size > 1024
            status = "PASS" if exists else "MISSING"
            if exists:
                passed += 1
            else:
                failed += 1
            results.append({"name": name, "status": status})
            print(f"  [{status:7s}] {name}")
        else:
            result = validate_glb(path, "buildings", verbose)
            status = "PASS" if result["valid"] and not result["issues"] else (
                "WARN" if result["valid"] else "FAIL"
            )
            if result["valid"]:
                passed += 1
            else:
                failed += 1
            results.append(result)
            issues_str = f" -- {'; '.join(result['issues'])}" if result["issues"] else ""
            print(f"  [{status:7s}] {name} ({result['size_kb']}KB){issues_str}")

    # Also check for unexpected .glb files in the directory
    if model_dir.exists():
        existing = {f.stem for f in model_dir.glob("*.glb")}
        expected = set(EXPECTED_BUILDINGS)
        extra = existing - expected
        if extra and verbose:
            print(f"\n  Extra files (not in expected list): {', '.join(sorted(extra))}")

    total = len(EXPECTED_BUILDINGS)
    found = passed
    min_required = MIN_COUNTS["buildings"]

    print(f"\n  Found: {found}/{total} expected | Min required: {min_required}")
    if found < min_required:
        print(f"  WARNING: Below minimum count ({found} < {min_required})")

    return passed, failed, total, results


def validate_props(quick: bool = False, verbose: bool = False) -> tuple:
    """Validate prop GLB assets."""
    model_dir = BASE_DIR / "models" / "props"
    results = []
    passed = 0
    failed = 0

    print("\n--- Props ---")
    print(f"Directory: {model_dir}")

    for name in EXPECTED_PROPS:
        path = model_dir / f"{name}.glb"

        if quick:
            exists = path.exists() and path.stat().st_size > 1024
            status = "PASS" if exists else "MISSING"
            if exists:
                passed += 1
            else:
                failed += 1
            results.append({"name": name, "status": status})
            print(f"  [{status:7s}] {name}")
        else:
            result = validate_glb(path, "props", verbose)
            status = "PASS" if result["valid"] and not result["issues"] else (
                "WARN" if result["valid"] else "FAIL"
            )
            if result["valid"]:
                passed += 1
            else:
                failed += 1
            results.append(result)
            issues_str = f" -- {'; '.join(result['issues'])}" if result["issues"] else ""
            print(f"  [{status:7s}] {name} ({result['size_kb']}KB){issues_str}")

    total = len(EXPECTED_PROPS)
    found = passed
    min_required = MIN_COUNTS["props"]

    print(f"\n  Found: {found}/{total} expected | Min required: {min_required}")
    if found < min_required:
        print(f"  WARNING: Below minimum count ({found} < {min_required})")

    return passed, failed, total, results


def validate_characters(
    quick: bool = False,
    verbose: bool = False,
    check_rig: bool = False,
) -> tuple:
    """Validate character GLB assets."""
    model_dir = BASE_DIR / "models" / "characters"
    results = []
    passed = 0
    failed = 0

    print("\n--- Characters ---")
    print(f"Directory: {model_dir}")

    for name in EXPECTED_CHARACTERS:
        path = model_dir / f"{name}.glb"

        if quick:
            exists = path.exists() and path.stat().st_size > 1024
            status = "PASS" if exists else "MISSING"
            if exists:
                passed += 1
            else:
                failed += 1
            results.append({"name": name, "status": status})
            print(f"  [{status:7s}] {name}")
        else:
            result = validate_glb(path, "characters", verbose)
            status = "PASS" if result["valid"] and not result["issues"] else (
                "WARN" if result["valid"] else "FAIL"
            )
            if result["valid"]:
                passed += 1
            else:
                failed += 1
            results.append(result)
            issues_str = f" -- {'; '.join(result['issues'])}" if result["issues"] else ""
            print(f"  [{status:7s}] {name} ({result['size_kb']}KB){issues_str}")

            # Check rigging if requested
            if check_rig and path.exists():
                rig_result = validate_glb_rigging(path, verbose)
                if not rig_result["has_skins"]:
                    print(f"           No rigging data (skins) found")
                    result["issues"].append("No rigging data")
                if not rig_result["has_animations"]:
                    print(f"           No animation data found")
                    result["issues"].append("No animation data")
                if rig_result["has_skins"] and rig_result["has_animations"]:
                    print(
                        f"           Rigged: {rig_result['skin_count']} skins, "
                        f"{rig_result['animation_count']} animations"
                    )

    total = len(EXPECTED_CHARACTERS)
    found = passed
    min_required = MIN_COUNTS["characters"]

    print(f"\n  Found: {found}/{total} expected | Min required: {min_required}")
    if found < min_required:
        print(f"  WARNING: Below minimum count ({found} < {min_required})")

    return passed, failed, total, results


def validate_textures(quick: bool = False, verbose: bool = False) -> tuple:
    """Validate PBR texture assets."""
    results = []
    passed = 0
    failed = 0

    print("\n--- Textures ---")

    for category, surfaces in TEXTURE_SURFACES.items():
        tex_dir = BASE_DIR / "textures" / category
        print(f"\n  {category}/")

        for surface in surfaces:
            for map_type in TEXTURE_MAP_TYPES:
                filename = f"{surface}_{map_type}.png"
                path = tex_dir / filename

                if quick:
                    exists = path.exists() and path.stat().st_size > 2000
                    status = "PASS" if exists else "MISSING"
                    if exists:
                        passed += 1
                    else:
                        failed += 1
                    results.append({"name": filename, "status": status})
                    print(f"    [{status:7s}] {filename}")
                else:
                    result = validate_texture(path, verbose)
                    if result["valid"] and not result["issues"]:
                        status = "PASS"
                        passed += 1
                    elif result["valid"]:
                        status = "WARN"
                        passed += 1  # warnings still count as passed
                    else:
                        status = "FAIL"
                        failed += 1
                    results.append(result)
                    issues_str = (
                        f" -- {'; '.join(result['issues'])}"
                        if result["issues"]
                        else ""
                    )
                    size_str = f"{result['size_bytes']}B" if result["size_bytes"] else "N/A"
                    print(f"    [{status:7s}] {filename} ({size_str}){issues_str}")

    total = passed + failed
    print(f"\n  Total texture files: {total} | Passed: {passed} | Failed: {failed}")

    return passed, failed, total, results


# ============================================================
# Main
# ============================================================


def main():
    parser = argparse.ArgumentParser(
        description="Validate assets for Liminal horror game"
    )
    parser.add_argument(
        "--category",
        choices=["buildings", "props", "characters", "textures", "all"],
        default="all",
        help="Asset category to validate (default: all)",
    )
    parser.add_argument(
        "--verbose",
        action="store_true",
        help="Print detailed info per asset",
    )
    parser.add_argument(
        "--quick",
        action="store_true",
        help="Check file existence only (skip format validation)",
    )
    parser.add_argument(
        "--check-rig",
        action="store_true",
        help="For characters, check if GLB contains rigging/animation data",
    )
    args = parser.parse_args()

    print("=" * 60)
    print("LIMINAL ASSET VALIDATION")
    print("=" * 60)

    total_passed = 0
    total_failed = 0
    total_assets = 0

    categories = (
        ["buildings", "props", "characters", "textures"]
        if args.category == "all"
        else [args.category]
    )

    for cat in categories:
        if cat == "buildings":
            p, f, t, _ = validate_buildings(args.quick, args.verbose)
        elif cat == "props":
            p, f, t, _ = validate_props(args.quick, args.verbose)
        elif cat == "characters":
            p, f, t, _ = validate_characters(args.quick, args.verbose, args.check_rig)
        elif cat == "textures":
            p, f, t, _ = validate_textures(args.quick, args.verbose)
        else:
            continue

        total_passed += p
        total_failed += f
        total_assets += t

    # Summary
    print("\n" + "=" * 60)
    print("SUMMARY")
    print("=" * 60)
    print(f"  Total assets checked: {total_assets}")
    print(f"  Passed: {total_passed}")
    print(f"  Failed: {total_failed}")

    # Count check per category
    if args.category in ("buildings", "all"):
        bldg_dir = BASE_DIR / "models" / "environment"
        if bldg_dir.exists():
            count = len(list(bldg_dir.glob("*.glb")))
            status = "OK" if count >= MIN_COUNTS["buildings"] else "BELOW MIN"
            print(f"  Buildings: {count} files ({status}, min {MIN_COUNTS['buildings']})")

    if args.category in ("props", "all"):
        props_dir = BASE_DIR / "models" / "props"
        if props_dir.exists():
            count = len(list(props_dir.glob("*.glb")))
            status = "OK" if count >= MIN_COUNTS["props"] else "BELOW MIN"
            print(f"  Props: {count} files ({status}, min {MIN_COUNTS['props']})")

    if args.category in ("characters", "all"):
        char_dir = BASE_DIR / "models" / "characters"
        if char_dir.exists():
            count = len(list(char_dir.glob("*.glb")))
            status = "OK" if count >= MIN_COUNTS["characters"] else "BELOW MIN"
            print(f"  Characters: {count} files ({status}, min {MIN_COUNTS['characters']})")

    if total_failed > 0:
        print(f"\n  RESULT: FAIL ({total_failed} issues found)")
        return 1
    else:
        print(f"\n  RESULT: PASS (all checks passed)")
        return 0


if __name__ == "__main__":
    sys.exit(main())
