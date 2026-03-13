#!/usr/bin/env python3
"""Generate all audio assets for Liminal horror game.

Generates ambient loops, monster sounds, footsteps, SFX, and music tracks
via ElevenLabs Sound Effects API and Suno API (sunoapi.org wrapper).

Usage:
    python3 generate_audio.py
    python3 generate_audio.py --section ambience
    python3 generate_audio.py --section monsters
    python3 generate_audio.py --section footsteps
    python3 generate_audio.py --section sfx
    python3 generate_audio.py --section music
    python3 generate_audio.py --dry-run
    python3 generate_audio.py --force

Requires ELEVENLABS_API_KEY and SUNO_API_KEY in .env file.
"""

import json
import os
import struct
import sys
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

ELEVENLABS_KEY = env["ELEVENLABS_API_KEY"]
SUNO_KEY = env["SUNO_API_KEY"]

BASE_DIR = Path(__file__).parent / "assets" / "audio"

# Placeholder detection thresholds
PLACEHOLDER_SIZE_WAV = 10000    # WAV placeholders are ~6,658 bytes
PLACEHOLDER_SIZE_MP3 = 5000     # MP3 files under 5KB are suspect
MIN_VALID_SIZE = 1000           # Anything under 1KB is definitely bad

# Rate limiting
ELEVENLABS_DELAY = 0.5   # seconds between ElevenLabs calls
SUNO_SUBMIT_DELAY = 2    # seconds between Suno submissions
SUNO_POLL_INTERVAL = 30  # seconds between Suno poll requests
SUNO_TIMEOUT = 600       # 10 minutes max per Suno task
RETRY_DELAY = 5          # seconds before retry on failure

# CLI flags
FORCE_REGEN = "--force" in sys.argv
DRY_RUN = "--dry-run" in sys.argv
SECTION_FILTER = None
for i, arg in enumerate(sys.argv):
    if arg == "--section" and i + 1 < len(sys.argv):
        SECTION_FILTER = sys.argv[i + 1]


# ============================================================
# API helpers
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
    except (urllib.error.URLError, TimeoutError) as e:
        print(f"  Network error: {e}")
        return None


def download_file(url, path):
    """Download a file from URL to path."""
    path.parent.mkdir(parents=True, exist_ok=True)
    urllib.request.urlretrieve(url, str(path))
    size_kb = path.stat().st_size / 1024
    print(f"  Downloaded: {path.name} ({size_kb:.0f} KB)")


def write_wav_header(pcm_data, sample_rate=44100, num_channels=1, bits_per_sample=16):
    """Wrap raw PCM data in a WAV file header."""
    data_size = len(pcm_data)
    byte_rate = sample_rate * num_channels * bits_per_sample // 8
    block_align = num_channels * bits_per_sample // 8
    header = struct.pack(
        '<4sI4s4sIHHIIHH4sI',
        b'RIFF',
        36 + data_size,
        b'WAVE',
        b'fmt ',
        16,
        1,  # PCM format
        num_channels,
        sample_rate,
        byte_rate,
        block_align,
        bits_per_sample,
        b'data',
        data_size,
    )
    return header + pcm_data


def should_generate(path, is_wav=False):
    """Check if a file needs to be (re)generated.

    Returns True if the file should be generated:
    - File doesn't exist
    - File is a placeholder (based on size thresholds)
    - --force flag is set
    """
    if FORCE_REGEN:
        return True
    if not path.exists():
        return True
    size = path.stat().st_size
    if size < MIN_VALID_SIZE:
        return True
    threshold = PLACEHOLDER_SIZE_WAV if is_wav else PLACEHOLDER_SIZE_MP3
    if size <= threshold:
        return True
    return False


# Track quota exhaustion globally to skip remaining calls
_elevenlabs_quota_exhausted = False


# ============================================================
# ElevenLabs generation
# ============================================================

def generate_elevenlabs(filename, prompt, duration, output_dir, output_format="mp3_44100_128", loop=False, prompt_influence=None):
    """Generate a single audio file via ElevenLabs Sound Effects API.

    Args:
        filename: Output filename (e.g., "wind_howl.mp3")
        prompt: Text description of the sound
        duration: Duration in seconds
        output_dir: Output directory Path
        output_format: ElevenLabs output format string
        loop: Whether to generate seamless loop (v2 model only)
        prompt_influence: Override prompt influence (0.0-1.0). If None, uses
            0.3 for loops, 0.4 for one-shots.

    Returns:
        True if successful, False otherwise
    """
    output_dir.mkdir(parents=True, exist_ok=True)
    output_path = output_dir / filename
    is_wav = filename.endswith(".wav")

    if not should_generate(output_path, is_wav=is_wav):
        print(f"  Skipping {filename} (already exists, {output_path.stat().st_size / 1024:.0f} KB)")
        return True

    global _elevenlabs_quota_exhausted
    if _elevenlabs_quota_exhausted:
        print(f"  Skipping {filename} (quota exhausted)")
        return False

    if DRY_RUN:
        influence = prompt_influence if prompt_influence is not None else (0.3 if loop else 0.4)
        print(f"  [DRY RUN] Would generate: {filename} ({duration}s, {'loop' if loop else 'one-shot'}, influence={influence})")
        return True

    print(f"  Generating: {filename} ({duration}s{', loop' if loop else ''}) ...")
    influence = prompt_influence if prompt_influence is not None else (0.3 if loop else 0.4)
    body = {
        "text": prompt,
        "duration_seconds": duration,
        "prompt_influence": influence,
        "output_format": output_format,
    }
    if loop:
        body["loop"] = True

    audio_data = api_request(
        "https://api.elevenlabs.io/v1/sound-generation",
        data=body,
        headers={"xi-api-key": ELEVENLABS_KEY},
    )

    if audio_data and isinstance(audio_data, bytes) and len(audio_data) > MIN_VALID_SIZE:
        # If WAV output requested but we got raw PCM, add WAV header
        if is_wav and not audio_data[:4] == b'RIFF':
            audio_data = write_wav_header(audio_data)
        output_path.write_bytes(audio_data)
        size_kb = len(audio_data) / 1024
        print(f"    OK: {size_kb:.0f} KB")
        return True

    # Check if quota exhausted (avoid wasting time on retries)
    if audio_data is None:
        # api_request prints the error; check if it was quota
        _elevenlabs_quota_exhausted = True
        print(f"    FAILED (possible quota exhaustion): {filename}")
        return False

    # Retry once for non-quota failures
    print(f"    First attempt failed, retrying in {RETRY_DELAY}s...")
    time.sleep(RETRY_DELAY)
    audio_data = api_request(
        "https://api.elevenlabs.io/v1/sound-generation",
        data=body,
        headers={"xi-api-key": ELEVENLABS_KEY},
    )
    if audio_data and isinstance(audio_data, bytes) and len(audio_data) > MIN_VALID_SIZE:
        if is_wav and not audio_data[:4] == b'RIFF':
            audio_data = write_wav_header(audio_data)
        output_path.write_bytes(audio_data)
        size_kb = len(audio_data) / 1024
        print(f"    OK (retry): {size_kb:.0f} KB")
        return True

    print(f"    FAILED: {filename}")
    return False


# ============================================================
# Section 1: Ambient Loops
# ============================================================

AMBIENCE_ITEMS = [
    ("horror_drone.mp3", "Deep subsonic horror drone, ominous low frequency rumble, dark unsettling atmosphere, sustained", 15),
    ("wind_howl.mp3", "Wind howling through empty abandoned streets, eerie desolate gusts, horror atmosphere, sustained", 15),
    ("rain_heavy.mp3", "Heavy rain downpour on pavement and rooftops, splashing on concrete, intense, continuous", 15),
    ("electrical_hum.mp3", "Low electrical hum, fluorescent light buzzing and flickering, indoor industrial, sustained", 15),
    ("distant_sirens.mp3", "Distant emergency sirens fading in and out, muffled through walls, eerie urban decay, sustained", 15),
    ("insects_night.mp3", "Nighttime crickets and insects chirping, distant, rural, eerie calm darkness, sustained", 15),
    ("water_drip.mp3", "Water dripping from pipes in empty building, echo in damp interior, slow drips, sustained", 10),
    ("building_creak.mp3", "Old building creaking and settling, wood and metal stress sounds, intermittent groaning, sustained", 15),
    ("pipe_rattle.mp3", "Metal pipes rattling and clanking in basement, steam pressure, industrial horror, sustained", 10),
    ("forest_rustle.mp3", "Wind through pine trees, rustling branches, isolated forest edge at night, eerie, sustained", 15),
    ("radio_static.mp3", "Faint radio static mixed with electronic interference, tuning through frequencies, unsettling, sustained", 10),
]


def generate_ambience():
    """Generate ambient loop audio files."""
    print("\n--- AMBIENT LOOPS (ElevenLabs) ---")
    output_dir = BASE_DIR / "ambience"
    ok = 0
    fail = 0
    for filename, prompt, duration in AMBIENCE_ITEMS:
        success = generate_elevenlabs(
            filename, prompt, duration, output_dir,
            output_format="mp3_44100_128", loop=True,
        )
        if success:
            ok += 1
        else:
            fail += 1
        if not DRY_RUN:
            time.sleep(ELEVENLABS_DELAY)
    print(f"  Ambience: {ok} OK, {fail} failed")
    return fail == 0


# ============================================================
# Section 2: Monster Sounds
# ============================================================

MONSTER_ITEMS = [
    # Echo Walker (renamed from Stalker)
    ("echo_walker_footsteps.mp3", "Heavy footstep on concrete, large creature walking slowly, reverberant, ominous", 1.5),
    ("echo_walker_teleport.mp3", "Sudden reality-warping whoosh, spatial distortion sound, brief dimensional shift, horror", 2),
    ("echo_walker_growl.mp3", "Low rumbling growl of a horror creature, threatening, deep bass, menacing", 3),
    ("echo_walker_breathing.mp3", "Deep raspy breathing of a large creature in darkness, horror monster, slow inhale exhale", 4),
    ("echo_walker_attack.mp3", "Violent monster lunge attack sound, sudden aggressive roar with impact, horror", 2),
    ("echo_walker_idle.mp3", "Quiet unsettling ambient presence, faint breathing and shifting weight, creature waiting in darkness", 5),
    # Lantern Widow
    ("lantern_widow_sobbing.mp3", "Faint distant female sobbing, ghostly muffled crying, eerie spectral weeping, horror", 5),
    ("lantern_widow_lantern_click.mp3", "Old metal lantern swinging and clicking, chain links tapping, rhythmic creaking, rusted", 3),
    ("lantern_widow_footsteps.mp3", "Slow dragging footstep, cloth trailing on ground, barefoot on concrete, ghostly shuffling", 1.5),
    ("lantern_widow_breathing.mp3", "Raspy shallow breathing, hooded figure, wheezy inhale, horror creature, ghostly", 4),
    ("lantern_widow_attack.mp3", "Sudden spectral shriek attack, ghostly scream with energy burst, horror monster", 2),
    ("lantern_widow_idle.mp3", "Faint sobbing mixed with lantern chain clinking, ghostly presence, subtle horror ambience", 5),
    # Window Man
    ("window_man_tapping.mp3", "Slow rhythmic finger tapping on glass window pane, deliberate, unsettling patience, horror", 3),
    ("window_man_glass_break.mp3", "Window glass shattering violently, single pane exploding inward, aggressive breach, horror", 2),
    ("window_man_charge.mp3", "Extremely fast running footsteps on pavement, monster in full sprint charge, terrifying aggression", 2),
    ("window_man_breathing.mp3", "Slow measured breathing through clenched teeth, sinister controlled breathing, horror", 4),
    ("window_man_laugh.mp3", "Low sinister chuckling, inhuman amused laughter, malicious, quiet, horror creature", 3),
    ("window_man_idle.mp3", "Faint scratching on glass from outside, fingernail scraping window, barely audible, horror", 4),
]


def generate_monsters():
    """Generate monster sound audio files."""
    print("\n--- MONSTER SOUNDS (ElevenLabs) ---")
    output_dir = BASE_DIR / "monsters"
    ok = 0
    fail = 0
    for filename, prompt, duration in MONSTER_ITEMS:
        success = generate_elevenlabs(
            filename, prompt, duration, output_dir,
            output_format="mp3_44100_128",
        )
        if success:
            ok += 1
        else:
            fail += 1
        if not DRY_RUN:
            time.sleep(ELEVENLABS_DELAY)
    print(f"  Monsters: {ok} OK, {fail} failed")
    return fail == 0


# ============================================================
# Section 3: Footstep Variants
# ============================================================

FOOTSTEP_ITEMS = [
    # (filename, prompt, duration_seconds, prompt_influence)
    # Duration increased from 0.5 to 1.0 -- ElevenLabs produces tiny files at 0.5s
    # prompt_influence raised to 0.5 for more control over short impacts
    # "close microphone" added to each prompt for clearer recordings
    # Concrete
    ("concrete_step_1.mp3", "Single footstep on concrete sidewalk, hard sole shoe, dry impact, urban, close microphone, short", 1.0, 0.5),
    ("concrete_step_2.mp3", "Single footstep on concrete floor, shoe impact, indoor, firm step, close microphone, short", 1.0, 0.5),
    ("concrete_step_3.mp3", "Single footstep on concrete pavement, hard surface impact, outdoor, close microphone, brief", 1.0, 0.5),
    # Grass
    ("grass_step_1.mp3", "Single footstep on grass, soft rustling, outdoor, quiet gentle step, close microphone, short", 1.0, 0.5),
    ("grass_step_2.mp3", "Single footstep on grass and leaves, light crunching, outdoor, close microphone, brief", 1.0, 0.5),
    ("grass_step_3.mp3", "Single footstep on wet grass, soft squelch, outdoor, muffled step, close microphone, short", 1.0, 0.5),
    # Metal
    ("metal_step_1.mp3", "Single footstep on metal grating, metallic ring, industrial, reverberant, close microphone, short", 1.0, 0.5),
    ("metal_step_2.mp3", "Single footstep on metal floor plate, hollow clang, industrial, close microphone, brief", 1.0, 0.5),
    ("metal_step_3.mp3", "Single footstep on metal catwalk, sharp metallic tap, resonant, close microphone, short", 1.0, 0.5),
    # Wood
    ("wood_step_1.mp3", "Single footstep on old wooden floorboard, slight creak, indoor, hollow, close microphone, short", 1.0, 0.5),
    ("wood_step_2.mp3", "Single footstep on wooden plank, board flexing, old floor, close microphone, brief creak", 1.0, 0.5),
    ("wood_step_3.mp3", "Single footstep on wooden stairs, wooden thud, slight creak, indoor, close microphone, short", 1.0, 0.5),
    # Gravel
    ("gravel_step_1.mp3", "Single footstep on gravel, crunching stones, outdoor, loose ground, close microphone, short", 1.0, 0.5),
    ("gravel_step_2.mp3", "Single footstep on gravel path, pebbles shifting, outdoor, close microphone, brief crunch", 1.0, 0.5),
    ("gravel_step_3.mp3", "Single footstep on gravel and loose stones, grinding crunch, outdoor, close microphone, short", 1.0, 0.5),
    # Water
    ("water_step_1.mp3", "Single footstep splashing in shallow water puddle, wet sloshing impact, close microphone, short", 1.0, 0.5),
    ("water_step_2.mp3", "Single footstep in shallow water, light splash, wet floor, close microphone, brief", 1.0, 0.5),
    ("water_step_3.mp3", "Single footstep wading through shallow water, splashing step, indoor flood, close microphone, short", 1.0, 0.5),
]


def generate_footsteps():
    """Generate footstep variant audio files."""
    print("\n--- FOOTSTEP VARIANTS (ElevenLabs) ---")
    output_dir = BASE_DIR / "footsteps"
    ok = 0
    fail = 0
    for item in FOOTSTEP_ITEMS:
        filename, prompt, duration = item[0], item[1], item[2]
        pi = item[3] if len(item) > 3 else None
        success = generate_elevenlabs(
            filename, prompt, duration, output_dir,
            output_format="mp3_44100_128",
            prompt_influence=pi,
        )
        if success:
            ok += 1
        else:
            fail += 1
        if not DRY_RUN:
            time.sleep(ELEVENLABS_DELAY)
    print(f"  Footsteps: {ok} OK, {fail} failed")
    return fail == 0


# ============================================================
# Section 4: Interaction SFX
# ============================================================

SFX_ITEMS = [
    ("door_open.mp3", "Heavy wooden door opening slowly, creaking rusty hinges, old abandoned building, horror", 2),
    ("door_close.mp3", "Heavy wooden door slamming shut, loud impact, reverberant, horror building", 1.5),
    ("door_locked.mp3", "Rattling a locked door handle, metal jiggling, door won't open, frustrated attempt", 1),
    ("switch_flip.mp3", "Mechanical switch being flipped, electrical breaker click with slight buzz, industrial", 1.0),
    ("generator_start.mp3", "Old diesel generator starting up, pull cord, engine coughing then catching, rumbling to life", 4),
    ("key_pickup.mp3", "Metal keys jingling when picked up, key ring clinking on surface, brief", 1),
    ("item_pickup.mp3", "Picking up a small object from a surface, brief scrape, subtle confirmation sound", 1.0),
    ("radio_tune.mp3", "Old radio tuning through frequencies, crackling static, dialing, analog knob turning", 3),
    ("heartbeat_slow.mp3", "Slow heartbeat pounding, calm but tense, muffled rhythmic pulse, anxiety building", 5),
    ("heartbeat_fast.mp3", "Fast heartbeat pounding rapidly, panic, adrenaline rush, loud muffled pulse, intense", 5),
    ("flashlight_click.mp3", "Flashlight clicking on and off, plastic button click, mechanical switch, brief", 1.0),
]


def generate_sfx():
    """Generate interaction SFX audio files."""
    print("\n--- INTERACTION SFX (ElevenLabs) ---")
    output_dir = BASE_DIR / "sfx"
    ok = 0
    fail = 0
    for filename, prompt, duration in SFX_ITEMS:
        success = generate_elevenlabs(
            filename, prompt, duration, output_dir,
            output_format="mp3_44100_128",
        )
        if success:
            ok += 1
        else:
            fail += 1
        if not DRY_RUN:
            time.sleep(ELEVENLABS_DELAY)
    print(f"  SFX: {ok} OK, {fail} failed")
    return fail == 0


# ============================================================
# Section 5: Music Tracks (Suno)
# ============================================================

# NOTE: Using Suno V5 model for better quality. If V5 is rejected by the API,
# manually change "model": "V5" to "model": "V4_5" as a fallback.
SUNO_TRACKS = [
    {
        "name": "ambient_drone",
        "customMode": True,
        "instrumental": True,
        "model": "V5",
        "style": "dark ambient, horror, subsonic drones, dissonant strings, atmospheric tension, cinematic, slow, unsettling, liminal spaces",
        "title": "Forgotten Streets",
        "negativeTags": "upbeat, happy, major key, pop, electronic dance, fast, vocals",
    },
    {
        "name": "chase_tension",
        "customMode": True,
        "instrumental": True,
        "model": "V5",
        "style": "intense horror chase music, pounding percussion, staccato strings, urgent tempo, dark orchestral, adrenaline, suspenseful, relentless",
        "title": "The Pursuit",
        "negativeTags": "calm, peaceful, ambient, slow, happy, electronic dance, pop, vocals",
    },
    {
        "name": "menu_theme",
        "customMode": True,
        "instrumental": True,
        "model": "V5",
        "style": "eerie piano melody, music box horror, unsettling calm, minor key, sparse arrangement, haunting, cinematic, liminal",
        "title": "Liminal",
        "negativeTags": "upbeat, major key, fast, loud, electronic, pop, dance, vocals",
    },
]


def generate_music():
    """Generate music tracks via Suno API."""
    print("\n--- MUSIC TRACKS (Suno) ---")
    music_dir = BASE_DIR / "music"
    music_dir.mkdir(parents=True, exist_ok=True)

    task_ids = []
    for track in SUNO_TRACKS:
        name = track["name"]
        # Check if we already have this track
        existing = list(music_dir.glob(f"{name}*.mp3"))
        real_existing = [f for f in existing if f.stat().st_size > MIN_VALID_SIZE]
        if real_existing and not FORCE_REGEN:
            print(f"  Skipping {name} (already exists: {[f.name for f in real_existing]})")
            continue

        if DRY_RUN:
            print(f"  [DRY RUN] Would generate music: {name}")
            continue

        print(f"  Submitting: {name}")
        body = {k: v for k, v in track.items() if k != "name"}
        body["callBackUrl"] = "https://httpbin.org/post"  # dummy callback

        resp = api_request(
            "https://api.sunoapi.org/api/v1/generate",
            data=body,
            headers={"Authorization": f"Bearer {SUNO_KEY}"},
        )
        if resp and resp.get("code") == 200:
            task_id = resp["data"]["taskId"]
            task_ids.append((task_id, name))
            print(f"    Task ID: {task_id}")
        else:
            print(f"    FAILED to submit: {resp}")
        time.sleep(SUNO_SUBMIT_DELAY)

    if not task_ids:
        if not DRY_RUN:
            print("  No new music to generate.")
        return True

    # Poll for completion
    print(f"\n  Waiting for {len(task_ids)} music tasks...")
    all_ok = True
    for task_id, name in task_ids:
        print(f"\n  Polling: {name} ({task_id[:12]}...)")
        start = time.time()
        success = False
        while time.time() - start < SUNO_TIMEOUT:
            resp = api_request(
                f"https://api.sunoapi.org/api/v1/generate/record-info?taskId={task_id}",
                headers={"Authorization": f"Bearer {SUNO_KEY}"},
                method="GET",
            )
            if not resp:
                time.sleep(SUNO_POLL_INTERVAL)
                continue

            data = resp.get("data", {})
            status = data.get("status", "UNKNOWN")
            elapsed = int(time.time() - start)
            print(f"    Status: {status} ({elapsed}s)")

            if status == "SUCCESS":
                suno_data = data.get("sunoData", [])
                for i, track_data in enumerate(suno_data):
                    audio_url = track_data.get("audioUrl") or track_data.get("streamAudioUrl")
                    if audio_url:
                        output_path = music_dir / f"{name}_{i + 1:02d}.mp3"
                        try:
                            download_file(audio_url, output_path)
                        except Exception as e:
                            print(f"    Download failed: {e}")
                success = True
                break
            elif "FAIL" in status.upper() or "ERROR" in status.upper():
                print(f"    Failed: {status}")
                break

            time.sleep(SUNO_POLL_INTERVAL)

        if not success:
            print(f"    FAILED or TIMEOUT: {name}")
            all_ok = False

    return all_ok


# ============================================================
# Summary
# ============================================================

def print_summary():
    """Print inventory of all audio files."""
    print("\n" + "=" * 60)
    print("AUDIO ASSET INVENTORY")
    print("=" * 60)

    categories = [
        ("ambience", BASE_DIR / "ambience"),
        ("monsters", BASE_DIR / "monsters"),
        ("footsteps", BASE_DIR / "footsteps"),
        ("sfx", BASE_DIR / "sfx"),
        ("music", BASE_DIR / "music"),
    ]

    total_files = 0
    total_size = 0
    for cat_name, cat_dir in categories:
        if not cat_dir.exists():
            print(f"\n  {cat_name}/: (directory not found)")
            continue
        files = sorted(f for f in cat_dir.iterdir() if f.suffix in (".mp3", ".wav") and not f.name.startswith("."))
        print(f"\n  {cat_name}/ ({len(files)} files):")
        for f in files:
            size = f.stat().st_size
            size_kb = size / 1024
            status = "OK" if size > MIN_VALID_SIZE else "BAD"
            print(f"    {f.name:45s} {size_kb:8.0f} KB  [{status}]")
            total_files += 1
            total_size += size

    print(f"\n  Total: {total_files} files, {total_size / 1024 / 1024:.1f} MB")


# ============================================================
# Main
# ============================================================

def main():
    print("=" * 60)
    print("LIMINAL AUDIO ASSET GENERATION")
    print("=" * 60)

    if DRY_RUN:
        print("  MODE: DRY RUN (no files will be generated)")
    if FORCE_REGEN:
        print("  MODE: FORCE (regenerating all files)")
    if SECTION_FILTER:
        print(f"  MODE: SECTION FILTER ({SECTION_FILTER})")

    sections = {
        "ambience": generate_ambience,
        "monsters": generate_monsters,
        "footsteps": generate_footsteps,
        "sfx": generate_sfx,
        "music": generate_music,
    }

    if SECTION_FILTER:
        if SECTION_FILTER not in sections:
            print(f"\n  ERROR: Unknown section '{SECTION_FILTER}'")
            print(f"  Valid sections: {', '.join(sections.keys())}")
            sys.exit(1)
        sections = {SECTION_FILTER: sections[SECTION_FILTER]}

    results = {}
    for name, func in sections.items():
        results[name] = func()

    # Print summary
    print_summary()

    print("\n" + "=" * 60)
    print("GENERATION COMPLETE")
    print("=" * 60)
    for name, ok in results.items():
        status = "OK" if ok else "SOME FAILURES"
        print(f"  {name:15s} {status}")


if __name__ == "__main__":
    main()
