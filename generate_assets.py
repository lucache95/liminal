#!/usr/bin/env python3
"""Asset generation script for Liminal horror game.
Generates 3D models (Meshy), SFX (ElevenLabs), and music (Suno) via APIs.
"""

import json
import os
import time
import urllib.request
import urllib.error
from pathlib import Path

# Load .env
env = {}
with open(Path(__file__).parent / ".env") as f:
    for line in f:
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            k, v = line.split("=", 1)
            env[k] = v

ELEVENLABS_KEY = env["ELEVENLABS_API_KEY"]
MESHY_KEY = env["MESHY_API_KEY"]
SUNO_KEY = env["SUNO_API_KEY"]

BASE_DIR = Path(__file__).parent / "assets"


def api_request(url, data=None, headers=None, method=None):
    """Make an API request and return parsed JSON or binary response."""
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


def download_file(url, path):
    """Download a file from URL to path."""
    path.parent.mkdir(parents=True, exist_ok=True)
    urllib.request.urlretrieve(url, str(path))
    size_kb = path.stat().st_size / 1024
    print(f"  Downloaded: {path.name} ({size_kb:.0f} KB)")


# ============================================================
# ELEVENLABS SFX
# ============================================================

SFX_ITEMS = [
    # Monster sounds
    ("monster_breathing_01.mp3", "Deep raspy breathing of a large creature in darkness, horror monster, slow inhale exhale", 4),
    ("monster_breathing_02.mp3", "Guttural wet breathing, creature lurking nearby, horror", 4),
    ("monster_growl_01.mp3", "Low rumbling growl of a horror creature, threatening, deep bass", 3),
    ("monster_growl_02.mp3", "Angry snarling growl, monster aggression, horror", 2),
    ("monster_footstep_heavy_01.mp3", "Heavy footstep on concrete, large creature walking slowly", 1.5),
    ("monster_footstep_heavy_02.mp3", "Heavy thudding footstep, monster approaching, stone floor", 1.5),
    ("monster_footstep_heavy_03.mp3", "Slow heavy boot stomp on pavement, ominous creature", 1.5),
    # Horror ambience
    ("horror_drone_01.mp3", "Deep subsonic horror drone, ominous low frequency rumble, dark atmosphere", 15),
    ("horror_drone_02.mp3", "Eerie dissonant ambient drone, creeping dread, minor key sustained tones", 15),
    ("creepy_whispers.mp3", "Distant unintelligible whispers echoing in empty hallway, ghostly horror", 8),
    # Jump scare / tension
    ("jumpscare_sting.mp3", "Sudden loud orchestral horror sting, sharp violins shrieking, jump scare", 2),
    ("heartbeat_tension.mp3", "Loud heartbeat pounding fast, anxiety tension, muffled", 6),
    # Environment sounds
    ("metal_scrape.mp3", "Metal scraping against concrete floor, eerie grinding sound", 3),
    ("glass_break.mp3", "Window glass shattering, single pane breaking", 2),
    ("radio_static.mp3", "Old radio tuning through static, crackling white noise, analog", 5),
    ("electrical_buzz.mp3", "Fluorescent light buzzing and flickering, electrical hum", 5),
    ("chain_rattle.mp3", "Heavy chains rattling and clinking, metal on metal", 3),
    ("floorboard_creak.mp3", "Old wooden floorboard creaking under weight, haunted house", 2),
]


def generate_elevenlabs_sfx():
    """Generate all SFX via ElevenLabs Sound Effects API."""
    print("\n=== ELEVENLABS SFX GENERATION ===")
    sfx_dir = BASE_DIR / "audio" / "sfx"
    sfx_dir.mkdir(parents=True, exist_ok=True)

    for filename, prompt, duration in SFX_ITEMS:
        output_path = sfx_dir / filename
        if output_path.exists() and output_path.stat().st_size > 1000:
            print(f"  Skipping {filename} (already exists)")
            continue

        print(f"  Generating: {filename} ({duration}s) ...")
        body = {
            "text": prompt,
            "duration_seconds": duration,
            "prompt_influence": 0.4,
        }
        audio_data = api_request(
            "https://api.elevenlabs.io/v1/sound-generation",
            data=body,
            headers={"xi-api-key": ELEVENLABS_KEY},
        )
        if audio_data and isinstance(audio_data, bytes):
            output_path.write_bytes(audio_data)
            size_kb = len(audio_data) / 1024
            print(f"    OK: {size_kb:.0f} KB")
        else:
            print(f"    FAILED: {filename}")
        time.sleep(0.5)  # rate limit courtesy


# ============================================================
# MESHY 3D MODELS
# ============================================================

MESHY_MODELS = [
    # Environment buildings
    ("environment", "abandoned_house_01", "Abandoned two-story wooden house, broken windows, peeling paint, horror, dark, weathered, overgrown"),
    ("environment", "abandoned_house_02", "Small derelict cottage, collapsed roof section, horror aesthetic, aged wood siding, dark"),
    ("environment", "church", "Small abandoned Gothic church, pointed arched windows, crumbling stone walls, dark horror atmosphere"),
    ("environment", "gas_station", "Abandoned rural gas station, rusted pumps, broken sign, horror, dark, weathered concrete"),
    ("environment", "warehouse", "Industrial warehouse building, corrugated metal walls, rusted, large sliding door, dark horror"),
    ("environment", "general_store", "Old abandoned general store building, wooden facade, broken display window, horror"),
    # Props
    ("props", "wooden_barrel", "Old weathered wooden barrel, rusted metal bands, dark stained wood, horror prop"),
    ("props", "dumpster", "Rusted green dumpster, dented metal, graffiti, urban horror prop"),
    ("props", "old_car", "Abandoned rusted sedan car from the 1970s, flat tires, broken headlights, horror"),
    ("props", "rusty_gate", "Wrought iron gate, rusted, gothic design, horror cemetery entrance"),
    ("props", "generator", "Portable diesel generator, industrial, weathered metal casing, cables"),
    ("props", "wooden_crate", "Old wooden shipping crate, nailed shut, stenciled text faded, dark wood"),
    ("props", "park_bench", "Weathered wooden park bench, peeling green paint, metal frame, abandoned"),
    ("props", "street_lamp", "Old cast iron street lamp post, single light, Victorian style, dark patina"),
    # Characters
    ("characters", "stalker_monster", "Grotesque tall humanoid horror monster, elongated limbs, pale grey skin, eyeless face with wide mouth of sharp teeth, hunched posture, tattered dark clothing remnants"),
]


def create_meshy_task(prompt, negative="cartoon, anime, bright, colorful, cute"):
    """Submit a text-to-3D preview task to Meshy."""
    resp = api_request(
        "https://api.meshy.ai/openapi/v2/text-to-3d",
        data={
            "mode": "preview",
            "prompt": prompt,
            "art_style": "realistic",
            "should_remesh": True,
            "negative_prompt": negative,
        },
        headers={"Authorization": f"Bearer {MESHY_KEY}"},
    )
    if resp and "result" in resp:
        return resp["result"]
    print(f"    Failed to create task: {resp}")
    return None


def poll_meshy_task(task_id, timeout=600):
    """Poll a Meshy task until completion."""
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
            print(f"    Task {task_id}: {status}")
            return None
        print(f"    {task_id[:8]}... {status} {progress}%")
        time.sleep(15)
    print(f"    Task {task_id}: TIMEOUT")
    return None


def generate_meshy_models():
    """Generate 3D models via Meshy API."""
    print("\n=== MESHY 3D MODEL GENERATION ===")

    # Submit all tasks first
    tasks = []
    for category, name, prompt in MESHY_MODELS:
        output_dir = BASE_DIR / "models" / category
        output_path = output_dir / f"{name}.glb"
        if output_path.exists() and output_path.stat().st_size > 1000:
            print(f"  Skipping {name} (already exists)")
            continue

        print(f"  Submitting: {name}")
        task_id = create_meshy_task(prompt)
        if task_id:
            tasks.append((task_id, category, name))
            print(f"    Task ID: {task_id}")
        time.sleep(1)  # stagger submissions

    if not tasks:
        print("  No new models to generate.")
        return

    print(f"\n  Waiting for {len(tasks)} models to generate...")

    # Poll all tasks
    for task_id, category, name in tasks:
        print(f"\n  Polling: {name} ({task_id[:8]}...)")
        result = poll_meshy_task(task_id)
        if result and "model_urls" in result:
            glb_url = result["model_urls"].get("glb")
            if glb_url:
                output_dir = BASE_DIR / "models" / category
                output_path = output_dir / f"{name}.glb"
                download_file(glb_url, output_path)


# ============================================================
# SUNO MUSIC
# ============================================================

SUNO_TRACKS = [
    {
        "name": "exploration_ambient",
        "customMode": True,
        "instrumental": True,
        "model": "V4_5",
        "style": "dark ambient, horror, subsonic drones, dissonant strings, atmospheric tension, cinematic, slow",
        "title": "Forgotten Streets",
        "negativeTags": "upbeat, happy, major key, pop, electronic dance, fast",
    },
    {
        "name": "chase_tension",
        "customMode": True,
        "instrumental": True,
        "model": "V4_5",
        "style": "intense horror chase music, pounding percussion, staccato strings, urgent tempo, dark orchestral, adrenaline",
        "title": "The Pursuit",
        "negativeTags": "calm, peaceful, ambient, slow, happy",
    },
    {
        "name": "menu_theme",
        "customMode": True,
        "instrumental": True,
        "model": "V4_5",
        "style": "eerie piano melody, music box horror, unsettling calm, minor key, sparse arrangement, haunting",
        "title": "Liminal",
        "negativeTags": "upbeat, major key, fast, loud, electronic",
    },
]


def generate_suno_music():
    """Generate music tracks via Suno API (sunoapi.org wrapper)."""
    print("\n=== SUNO MUSIC GENERATION ===")
    music_dir = BASE_DIR / "audio" / "music"
    music_dir.mkdir(parents=True, exist_ok=True)

    task_ids = []
    for track in SUNO_TRACKS:
        name = track["name"]
        # Check if we already have this track
        existing = list(music_dir.glob(f"{name}*.mp3"))
        if existing:
            print(f"  Skipping {name} (already exists)")
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
            print(f"    FAILED: {resp}")
        time.sleep(2)

    if not task_ids:
        print("  No new music to generate.")
        return

    # Poll for completion
    print(f"\n  Waiting for {len(task_ids)} music tasks...")
    for task_id, name in task_ids:
        print(f"\n  Polling: {name} ({task_id[:8]}...)")
        start = time.time()
        while time.time() - start < 600:
            resp = api_request(
                f"https://api.sunoapi.org/api/v1/generate/record-info?taskId={task_id}",
                headers={"Authorization": f"Bearer {SUNO_KEY}"},
                method="GET",
            )
            if not resp:
                time.sleep(15)
                continue

            status = resp.get("data", {}).get("status", "UNKNOWN")
            print(f"    Status: {status}")

            if status == "SUCCESS":
                suno_data = resp["data"].get("sunoData", [])
                for i, track_data in enumerate(suno_data):
                    audio_url = track_data.get("audioUrl") or track_data.get("streamAudioUrl")
                    if audio_url:
                        output_path = music_dir / f"{name}_{i + 1:02d}.mp3"
                        download_file(audio_url, output_path)
                break
            elif "FAILED" in status or "ERROR" in status:
                print(f"    Failed: {status}")
                break
            time.sleep(30)


# ============================================================
# MAIN
# ============================================================

if __name__ == "__main__":
    print("=" * 60)
    print("LIMINAL ASSET GENERATION")
    print("=" * 60)

    # Phase 1: ElevenLabs SFX (fastest, synchronous)
    generate_elevenlabs_sfx()

    # Phase 2: Meshy 3D models (async, takes ~3 min each)
    generate_meshy_models()

    # Phase 3: Suno music (async, takes ~2-5 min each)
    generate_suno_music()

    print("\n" + "=" * 60)
    print("GENERATION COMPLETE")
    print("=" * 60)
