#!/usr/bin/env python3
"""Town scene validation script for Liminal.

Validates material files, building instances, prop counts, and navmesh
configuration by parsing .tscn and .tres files as text.

Usage:
    python3 validate_town.py --check materials
    python3 validate_town.py --check buildings
    python3 validate_town.py --check props
    python3 validate_town.py --check navmesh
    python3 validate_town.py --quick
    python3 validate_town.py --verbose
"""

import argparse
import os
import re
import sys
from pathlib import Path
from typing import List, Tuple

SCRIPT_DIR = Path(__file__).parent.resolve()
MATERIALS_DIR = SCRIPT_DIR / "materials"
TOWN_SCENE = SCRIPT_DIR / "levels" / "town" / "town.tscn"

EXPECTED_MATERIALS = [
    "grass", "concrete_wall", "asphalt", "old_wood", "rusty_metal",
    "dark_creature", "brick", "dirt", "tile", "wallpaper",
    "metal_clean", "roof_shingles",
]

BUILDING_NODES = [
    "Shop01", "Shop02", "Shop03", "Shop04",
    "MainBuilding", "ChurchBuilding",
    "Warehouse01", "Warehouse02",
    "House01", "House02", "House03",
    "MotelMain", "TowerBase",
]

REQUIRED_MAT_FIELDS = [
    "albedo_texture",
    "normal_texture",
    "roughness_texture",
]


def check_materials(verbose: bool = False) -> Tuple[bool, str]:
    """Verify all material .tres files have PBR texture references."""
    if not MATERIALS_DIR.is_dir():
        return False, f"FAIL: Materials directory not found: {MATERIALS_DIR}"

    all_pass = True
    messages: List[str] = []

    for name in EXPECTED_MATERIALS:
        fpath = MATERIALS_DIR / f"{name}.tres"
        if not fpath.is_file():
            messages.append(f"  FAIL: Missing material file: {fpath.name}")
            all_pass = False
            continue

        content = fpath.read_text()
        file_ok = True

        for field in REQUIRED_MAT_FIELDS:
            pattern = rf'{field}\s*=\s*ExtResource\('
            if not re.search(pattern, content):
                messages.append(f"  FAIL: {fpath.name} missing {field} ExtResource")
                file_ok = False
                all_pass = False

        if "texture_filter = 0" not in content:
            messages.append(f"  FAIL: {fpath.name} missing texture_filter = 0")
            file_ok = False
            all_pass = False

        if file_ok and verbose:
            messages.append(f"  PASS: {fpath.name}")

    status = "PASS" if all_pass else "FAIL"
    summary = f"[{status}] Materials: {len(EXPECTED_MATERIALS)} expected"
    if messages:
        summary += "\n" + "\n".join(messages)
    return all_pass, summary


def check_buildings(verbose: bool = False) -> Tuple[bool, str]:
    """Verify building placeholder nodes have .glb instance references."""
    if not TOWN_SCENE.is_file():
        return False, f"FAIL: Town scene not found: {TOWN_SCENE}"

    content = TOWN_SCENE.read_text()
    all_pass = True
    messages: List[str] = []
    found = 0

    for node_name in BUILDING_NODES:
        # Look for node with this name that has an instance ExtResource
        # Pattern: [node name="Shop01" ... instance=ExtResource(...)]
        pattern = rf'\[node\s+name="{node_name}"[^\]]*instance\s*=\s*ExtResource\('
        if re.search(pattern, content):
            found += 1
            if verbose:
                messages.append(f"  PASS: {node_name} has instance")
        else:
            # Check if node exists at all
            node_pattern = rf'\[node\s+name="{node_name}"'
            if re.search(node_pattern, content):
                messages.append(f"  FAIL: {node_name} exists but no .glb instance")
            else:
                messages.append(f"  FAIL: {node_name} node not found")
            all_pass = False

    status = "PASS" if all_pass else "FAIL"
    summary = f"[{status}] Buildings: {found}/{len(BUILDING_NODES)} with instances"
    if messages:
        summary += "\n" + "\n".join(messages)
    return all_pass, summary


def check_props(verbose: bool = False) -> Tuple[bool, str]:
    """Count prop instances referencing assets/models/props/ paths."""
    if not TOWN_SCENE.is_file():
        return False, f"FAIL: Town scene not found: {TOWN_SCENE}"

    content = TOWN_SCENE.read_text()
    TARGET = 40

    # Find ext_resource entries referencing props
    prop_resources = re.findall(
        r'\[ext_resource\s+[^\]]*path\s*=\s*"res://assets/models/props/[^"]*"[^\]]*id\s*=\s*"([^"]*)"',
        content,
    )
    # Also match alternate ordering
    prop_resources += re.findall(
        r'\[ext_resource\s+[^\]]*id\s*=\s*"([^"]*)"[^\]]*path\s*=\s*"res://assets/models/props/',
        content,
    )
    prop_ids = set(prop_resources)

    # Count node instances referencing those IDs
    instance_count = 0
    for pid in prop_ids:
        instances = re.findall(
            rf'instance\s*=\s*ExtResource\(\s*"{re.escape(pid)}"\s*\)', content
        )
        instance_count += len(instances)

    passed = instance_count >= TARGET
    status = "PASS" if passed else "FAIL"
    summary = f"[{status}] Props: {instance_count}/{TARGET} target instances"

    if verbose:
        summary += f"\n  Unique prop resources: {len(prop_ids)}"
        summary += f"\n  Total prop instances: {instance_count}"

    return passed, summary


def check_navmesh(verbose: bool = False) -> Tuple[bool, str]:
    """Verify NavigationMesh configuration in town scene."""
    if not TOWN_SCENE.is_file():
        return False, f"FAIL: Town scene not found: {TOWN_SCENE}"

    content = TOWN_SCENE.read_text()
    all_pass = True
    messages: List[str] = []

    # Check for NavigationMesh sub_resource
    has_navmesh = "NavigationMesh" in content
    if not has_navmesh:
        messages.append("  FAIL: No NavigationMesh sub_resource found")
        all_pass = False
    elif verbose:
        messages.append("  PASS: NavigationMesh sub_resource found")

    # Check agent_max_climb
    if "agent_max_climb" in content:
        if verbose:
            match = re.search(r'agent_max_climb\s*=\s*([^\n]+)', content)
            val = match.group(1) if match else "?"
            messages.append(f"  PASS: agent_max_climb = {val}")
    else:
        messages.append("  FAIL: agent_max_climb not set")
        all_pass = False

    # Check cell_size
    if "cell_size" in content:
        if verbose:
            match = re.search(r'cell_size\s*=\s*([^\n]+)', content)
            val = match.group(1) if match else "?"
            messages.append(f"  PASS: cell_size = {val}")
    else:
        messages.append("  FAIL: cell_size not set")
        all_pass = False

    # Check geometry_source_geometry_mode
    if "geometry_source_geometry_mode" in content:
        if verbose:
            messages.append("  PASS: geometry_source_geometry_mode set")
    else:
        messages.append("  FAIL: geometry_source_geometry_mode not set")
        all_pass = False

    status = "PASS" if all_pass else "FAIL"
    summary = f"[{status}] NavMesh: configuration"
    if messages:
        summary += "\n" + "\n".join(messages)
    return all_pass, summary


CHECK_MAP = {
    "materials": check_materials,
    "buildings": check_buildings,
    "props": check_props,
    "navmesh": check_navmesh,
}


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate Liminal town scene")
    parser.add_argument(
        "--check",
        choices=list(CHECK_MAP.keys()),
        help="Run a specific check",
    )
    parser.add_argument(
        "--quick",
        action="store_true",
        help="Run all checks, exit 0 if all pass",
    )
    parser.add_argument(
        "--verbose",
        action="store_true",
        help="Run all checks with detailed output",
    )
    args = parser.parse_args()

    if not any([args.check, args.quick, args.verbose]):
        parser.print_help()
        return 1

    checks_to_run = [args.check] if args.check else list(CHECK_MAP.keys())
    verbose = args.verbose or bool(args.check)

    all_pass = True
    for name in checks_to_run:
        passed, message = CHECK_MAP[name](verbose=verbose)
        print(message)
        if not passed:
            all_pass = False

    if args.quick or args.verbose:
        print()
        if all_pass:
            print("ALL CHECKS PASSED")
        else:
            print("SOME CHECKS FAILED")

    return 0 if all_pass else 1


if __name__ == "__main__":
    sys.exit(main())
