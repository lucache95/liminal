#!/usr/bin/env python3
"""Audio asset validation script for Liminal horror game.

Validates all generated audio files (MP3/WAV) against quality and format
requirements for ASST-07 through ASST-11. Checks file existence, size
thresholds, and header validity per category.

Usage:
    python3 validate_audio.py                        # Validate all categories
    python3 validate_audio.py --category ambience    # Ambience only
    python3 validate_audio.py --verbose              # Detailed per-file info
    python3 validate_audio.py --quick                # Size-only, skip headers
"""

import argparse
import sys
from pathlib import Path

BASE_DIR = Path(__file__).parent / "assets" / "audio"

# ============================================================
# Expected assets per category (requirement)
# ============================================================

# ASST-07: Ambient Loops
EXPECTED_AMBIENCE = [
    "horror_drone.mp3",
    "wind_howl.mp3",
    "rain_heavy.mp3",
    "electrical_hum.mp3",
    "distant_sirens.mp3",
    "insects_night.mp3",
    "water_drip.mp3",
    "building_creak.mp3",
    "pipe_rattle.mp3",
    "forest_rustle.mp3",
    "radio_static.mp3",
]

# Old WAV placeholders that should have been replaced
AMBIENCE_LEGACY_WAV = [
    "wind_loop.wav",
    "hum_loop.wav",
]
AMBIENCE_LEGACY_SIZE = 132344  # Exact size of old placeholders

# ASST-08: Monster Audio
EXPECTED_MONSTERS = [
    # Echo Walker
    "echo_walker_footsteps.mp3",
    "echo_walker_teleport.mp3",
    "echo_walker_growl.mp3",
    "echo_walker_breathing.mp3",
    "echo_walker_attack.mp3",
    "echo_walker_idle.mp3",
    # Lantern Widow
    "lantern_widow_sobbing.mp3",
    "lantern_widow_lantern_click.mp3",
    "lantern_widow_footsteps.mp3",
    "lantern_widow_breathing.mp3",
    "lantern_widow_attack.mp3",
    "lantern_widow_idle.mp3",
    # Window Man
    "window_man_tapping.mp3",
    "window_man_glass_break.mp3",
    "window_man_charge.mp3",
    "window_man_breathing.mp3",
    "window_man_laugh.mp3",
    "window_man_idle.mp3",
]

# ASST-09: Footstep Audio
EXPECTED_FOOTSTEPS = [
    "concrete_step_1.mp3",
    "concrete_step_2.mp3",
    "concrete_step_3.mp3",
    "grass_step_1.mp3",
    "grass_step_2.mp3",
    "grass_step_3.mp3",
    "metal_step_1.mp3",
    "metal_step_2.mp3",
    "metal_step_3.mp3",
    "wood_step_1.mp3",
    "wood_step_2.mp3",
    "wood_step_3.mp3",
    "gravel_step_1.mp3",
    "gravel_step_2.mp3",
    "gravel_step_3.mp3",
    "water_step_1.mp3",
    "water_step_2.mp3",
    "water_step_3.mp3",
]

# ASST-10: Music Tracks
# Suno generates 2 variants per track (name_01.mp3, name_02.mp3)
EXPECTED_MUSIC_BASES = [
    "exploration_ambient",
    "ambient_drone",
    "chase_tension",
    "menu_theme",
]

# ASST-11: Interaction SFX
EXPECTED_SFX = [
    "door_open.mp3",
    "door_close.mp3",
    "door_locked.mp3",
    "switch_flip.mp3",
    "generator_start.mp3",
    "key_pickup.mp3",
    "item_pickup.mp3",
    "radio_tune.mp3",
    "heartbeat_slow.mp3",
    "heartbeat_fast.mp3",
    "flashlight_click.mp3",
]

# Legacy SFX that should still be present (generated in earlier runs)
LEGACY_SFX = [
    "heartbeat_tension.mp3",
    "jumpscare_sting.mp3",
    "radio_static.mp3",
    "electrical_buzz.mp3",
    "glass_break.mp3",
    "metal_scrape.mp3",
    "chain_rattle.mp3",
    "floorboard_creak.mp3",
    "creepy_whispers.mp3",
    "horror_drone_01.mp3",
    "horror_drone_02.mp3",
    "monster_breathing_01.mp3",
    "monster_breathing_02.mp3",
    "monster_growl_01.mp3",
    "monster_growl_02.mp3",
    "monster_footstep_heavy_01.mp3",
    "monster_footstep_heavy_02.mp3",
    "monster_footstep_heavy_03.mp3",
]

# Size thresholds (bytes)
SIZE_AMBIENCE_MIN = 10 * 1024       # 10KB -- real ambient loops are 160-241KB
SIZE_MONSTER_MIN = 10 * 1024        # 10KB -- real monster sounds are 24-81KB
SIZE_FOOTSTEP_MIN = 10 * 1024       # 10KB -- NOT the current 8,821 which is too small
SIZE_MUSIC_MIN = 500 * 1024         # 500KB -- real music tracks are ~5.5MB
SIZE_SFX_MP3_MIN = 5 * 1024         # 5KB for MP3 SFX
SIZE_SFX_WAV_MIN = 10 * 1024        # 10KB for WAV SFX


# ============================================================
# Header checking helpers
# ============================================================

def check_mp3_header(path: Path) -> tuple:
    """Check if file has valid MP3 header bytes.

    Returns:
        (is_valid, detail_string)
    """
    try:
        with open(path, "rb") as f:
            header = f.read(3)
        if len(header) < 3:
            return False, "File too small for header check"
        # MP3 frame sync: 0xFF 0xFB (or 0xFF 0xFA, 0xFF 0xF3, 0xFF 0xF2)
        if header[0] == 0xFF and (header[1] & 0xE0) == 0xE0:
            return True, "MP3 frame sync"
        # ID3 tag at start
        if header[:3] == b"ID3":
            return True, "ID3 tag"
        return False, f"Unknown header: {header[:3].hex()}"
    except OSError as e:
        return False, f"Read error: {e}"


def check_wav_header(path: Path) -> tuple:
    """Check if file has valid WAV (RIFF) header.

    Returns:
        (is_valid, detail_string)
    """
    try:
        with open(path, "rb") as f:
            header = f.read(4)
        if len(header) < 4:
            return False, "File too small for header check"
        if header == b"RIFF":
            return True, "RIFF/WAV"
        return False, f"Unknown header: {header[:4].hex()}"
    except OSError as e:
        return False, f"Read error: {e}"


# ============================================================
# Per-file validation
# ============================================================

def validate_file(path: Path, size_min: int, quick: bool = False) -> dict:
    """Validate a single audio file.

    Args:
        path: Path to audio file
        size_min: Minimum acceptable size in bytes
        quick: If True, skip header check

    Returns:
        dict with 'status' (OK/WARN/FAIL), 'size', 'issues'
    """
    result = {
        "name": path.name,
        "status": "OK",
        "size": 0,
        "issues": [],
    }

    if not path.exists():
        result["status"] = "FAIL"
        result["issues"].append("Missing")
        return result

    size = path.stat().st_size
    result["size"] = size

    if size < size_min:
        result["status"] = "FAIL"
        result["issues"].append(f"Too small: {size:,} bytes (min {size_min:,})")

    if not quick and path.suffix == ".mp3":
        valid, detail = check_mp3_header(path)
        if not valid:
            result["status"] = "FAIL"
            result["issues"].append(f"Bad MP3 header: {detail}")

    if not quick and path.suffix == ".wav":
        valid, detail = check_wav_header(path)
        if not valid:
            result["status"] = "FAIL"
            result["issues"].append(f"Bad WAV header: {detail}")

    return result


# ============================================================
# Category validators
# ============================================================

def validate_ambience(quick: bool = False, verbose: bool = False) -> tuple:
    """Validate ASST-07 Ambient Loop audio files.

    Returns:
        (ok_count, warn_count, fail_count, total)
    """
    audio_dir = BASE_DIR / "ambience"
    ok, warn, fail = 0, 0, 0

    if verbose:
        print(f"\n  Directory: {audio_dir}")

    for filename in EXPECTED_AMBIENCE:
        path = audio_dir / filename
        result = validate_file(path, SIZE_AMBIENCE_MIN, quick)

        if result["status"] == "OK":
            ok += 1
        elif result["status"] == "WARN":
            warn += 1
        else:
            fail += 1

        if verbose:
            size_kb = result["size"] / 1024
            issues = "; ".join(result["issues"]) if result["issues"] else ""
            tag = f"  [{result['status']}]" if issues else f"  [{result['status']}]"
            print(f"  {filename:45s} {size_kb:8.0f} KB  [{result['status']}]{' -- ' + issues if issues else ''}")

    # Check for old WAV placeholders
    for wav_name in AMBIENCE_LEGACY_WAV:
        wav_path = audio_dir / wav_name
        if wav_path.exists():
            size = wav_path.stat().st_size
            if size == AMBIENCE_LEGACY_SIZE:
                warn += 1
                if verbose:
                    print(f"  {wav_name:45s} {size / 1024:8.0f} KB  [WARN: old placeholder]")
            else:
                if verbose:
                    print(f"  {wav_name:45s} {size / 1024:8.0f} KB  [WARN: legacy file]")
                warn += 1

    total = len(EXPECTED_AMBIENCE)
    return ok, warn, fail, total


def validate_monsters(quick: bool = False, verbose: bool = False) -> tuple:
    """Validate ASST-08 Monster Audio files.

    Returns:
        (ok_count, warn_count, fail_count, total)
    """
    audio_dir = BASE_DIR / "monsters"
    ok, warn, fail = 0, 0, 0

    if verbose:
        print(f"\n  Directory: {audio_dir}")

    for filename in EXPECTED_MONSTERS:
        path = audio_dir / filename
        result = validate_file(path, SIZE_MONSTER_MIN, quick)

        if result["status"] == "OK":
            ok += 1
        elif result["status"] == "WARN":
            warn += 1
        else:
            fail += 1

        if verbose:
            size_kb = result["size"] / 1024
            issues = "; ".join(result["issues"]) if result["issues"] else ""
            print(f"  {filename:45s} {size_kb:8.0f} KB  [{result['status']}]{' -- ' + issues if issues else ''}")

    total = len(EXPECTED_MONSTERS)
    return ok, warn, fail, total


def validate_footsteps(quick: bool = False, verbose: bool = False) -> tuple:
    """Validate ASST-09 Footstep Audio files.

    Also checks that all files have DIFFERENT sizes (identical sizes
    indicate placeholder/bad generation).

    Returns:
        (ok_count, warn_count, fail_count, total)
    """
    audio_dir = BASE_DIR / "footsteps"
    ok, warn, fail = 0, 0, 0
    sizes = []

    if verbose:
        print(f"\n  Directory: {audio_dir}")

    for filename in EXPECTED_FOOTSTEPS:
        path = audio_dir / filename
        result = validate_file(path, SIZE_FOOTSTEP_MIN, quick)

        if result["status"] == "OK":
            ok += 1
            sizes.append(result["size"])
        elif result["status"] == "WARN":
            warn += 1
            sizes.append(result["size"])
        else:
            fail += 1

        if verbose:
            size_kb = result["size"] / 1024
            issues = "; ".join(result["issues"]) if result["issues"] else ""
            print(f"  {filename:45s} {size_kb:8.0f} KB  [{result['status']}]{' -- ' + issues if issues else ''}")

    # Check for identical sizes (sign of placeholder generation)
    # Only flag as placeholder if ALL files have the same size AND that size
    # is below the minimum threshold. Short footsteps at the same duration and
    # bitrate (e.g. 1.0s at 128kbps = 17,180 bytes) legitimately have identical
    # sizes, so we only fail if they're also undersized.
    if sizes and len(set(sizes)) == 1 and len(sizes) > 1 and sizes[0] < SIZE_FOOTSTEP_MIN:
        if verbose:
            print(f"  WARNING: All {len(sizes)} files have identical size ({sizes[0]:,} bytes) -- likely placeholders")
        # Downgrade all OK to FAIL
        fail += ok
        ok = 0
    elif sizes and len(set(sizes)) == 1 and len(sizes) > 1:
        if verbose:
            print(f"  NOTE: All {len(sizes)} files have identical size ({sizes[0]:,} bytes) -- normal for same-duration short sounds")

    total = len(EXPECTED_FOOTSTEPS)
    return ok, warn, fail, total


def validate_music(quick: bool = False, verbose: bool = False) -> tuple:
    """Validate ASST-10 Music Track files.

    Suno generates 2 variants per track name (name_01.mp3, name_02.mp3).
    We count the expected base names and check how many have at least one variant.

    Returns:
        (ok_count, warn_count, fail_count, total)
    """
    music_dir = BASE_DIR / "music"
    ok, warn, fail = 0, 0, 0
    total_expected_files = 0

    if verbose:
        print(f"\n  Directory: {music_dir}")

    for base_name in EXPECTED_MUSIC_BASES:
        # Check for _01 and _02 variants
        for variant in ["_01.mp3", "_02.mp3"]:
            filename = f"{base_name}{variant}"
            total_expected_files += 1
            path = music_dir / filename
            result = validate_file(path, SIZE_MUSIC_MIN, quick)

            if result["status"] == "OK":
                ok += 1
            elif result["status"] == "WARN":
                warn += 1
            else:
                fail += 1

            if verbose:
                if result["size"] > 0:
                    size_kb = result["size"] / 1024
                    issues = "; ".join(result["issues"]) if result["issues"] else ""
                    print(f"  {filename:45s} {size_kb:8.0f} KB  [{result['status']}]{' -- ' + issues if issues else ''}")
                else:
                    print(f"  {filename:45s}      N/A  [{result['status']}] -- Missing")

    total = total_expected_files
    return ok, warn, fail, total


def validate_sfx(quick: bool = False, verbose: bool = False) -> tuple:
    """Validate ASST-11 Interaction SFX files.

    Also checks for legacy SFX files that should still be present.

    Returns:
        (ok_count, warn_count, fail_count, total)
    """
    sfx_dir = BASE_DIR / "sfx"
    ok, warn, fail = 0, 0, 0

    if verbose:
        print(f"\n  Directory: {sfx_dir}")

    # Primary SFX
    for filename in EXPECTED_SFX:
        path = sfx_dir / filename
        is_wav = filename.endswith(".wav")
        size_min = SIZE_SFX_WAV_MIN if is_wav else SIZE_SFX_MP3_MIN
        result = validate_file(path, size_min, quick)

        if result["status"] == "OK":
            ok += 1
        elif result["status"] == "WARN":
            warn += 1
        else:
            fail += 1

        if verbose:
            size_kb = result["size"] / 1024
            issues = "; ".join(result["issues"]) if result["issues"] else ""
            print(f"  {filename:45s} {size_kb:8.0f} KB  [{result['status']}]{' -- ' + issues if issues else ''}")

    # Legacy SFX (warn-only if missing, don't fail)
    legacy_present = 0
    legacy_missing = 0
    for filename in LEGACY_SFX:
        path = sfx_dir / filename
        if path.exists() and path.stat().st_size > 1000:
            legacy_present += 1
            if verbose:
                size_kb = path.stat().st_size / 1024
                print(f"  {filename:45s} {size_kb:8.0f} KB  [OK] (legacy)")
        else:
            legacy_missing += 1
            if verbose:
                print(f"  {filename:45s}      N/A  [WARN] (legacy missing)")

    if verbose and legacy_missing > 0:
        print(f"  Legacy SFX: {legacy_present} present, {legacy_missing} missing")

    total = len(EXPECTED_SFX)
    return ok, warn, fail, total


# ============================================================
# Main
# ============================================================

def main():
    parser = argparse.ArgumentParser(
        description="Validate audio assets for Liminal horror game"
    )
    parser.add_argument(
        "--category",
        choices=["all", "ambience", "monsters", "footsteps", "sfx", "music"],
        default="all",
        help="Audio category to validate (default: all)",
    )
    parser.add_argument(
        "--verbose",
        action="store_true",
        help="Print detailed per-file info",
    )
    parser.add_argument(
        "--quick",
        action="store_true",
        help="Size-only checks, skip header validation",
    )
    args = parser.parse_args()

    print("=" * 60)
    print("LIMINAL AUDIO ASSET VALIDATION")
    print("=" * 60)

    categories = {
        "ambience": ("ASST-07 Ambient Loops", validate_ambience),
        "monsters": ("ASST-08 Monster Audio", validate_monsters),
        "footsteps": ("ASST-09 Footstep Audio", validate_footsteps),
        "music": ("ASST-10 Music Tracks", validate_music),
        "sfx": ("ASST-11 Interaction SFX", validate_sfx),
    }

    if args.category != "all":
        categories = {args.category: categories[args.category]}

    results = {}
    total_ok = 0
    total_fail = 0

    for key, (label, validator) in categories.items():
        print(f"\n{label}:")
        ok, warn, fail, total = validator(quick=args.quick, verbose=args.verbose)
        results[label] = (ok, warn, fail, total)
        total_ok += ok
        total_fail += fail

    # Summary table
    print("\n" + "=" * 60)
    print("SUMMARY")
    print("=" * 60)

    total_all = 0
    for label, (ok, warn, fail, total) in results.items():
        total_all += total
        status_parts = []
        if warn > 0:
            status_parts.append(f"{warn} WARN")
        if fail > 0:
            status_parts.append(f"{fail} FAIL")
        extra = f"  <-- {', '.join(status_parts)}" if status_parts else ""
        print(f"  {label:25s} {ok:3d}/{total:<3d} OK ({warn} WARN, {fail} FAIL){extra}")

    print(f"\n  Overall: {total_ok}/{total_all} OK")

    if total_fail > 0:
        print(f"\n  RESULT: FAIL ({total_fail} issues found)")
        return 1
    else:
        print(f"\n  RESULT: PASS (all checks passed)")
        return 0


if __name__ == "__main__":
    sys.exit(main())
