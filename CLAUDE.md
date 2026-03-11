# Liminal — Godot 4.4 Horror Game

## Project
First-person horror/exploration game. Abandoned liminal town, hidden escape objectives, stalker monster with sight/sound/light AI.

## Stack
- Godot 4.4, Forward+ renderer, GDScript
- Pure GDScript state machine (no LimboAI addon)
- AI-generated assets: Meshy (props), Tripo (characters), ElevenLabs (SFX), Suno (music)

## Architecture
- **Autoloads**: EventBus (signals), GameManager (state/pause), AudioManager (buses/layers), SceneManager (transitions), ObjectiveManager (run objectives)
- **Signal-driven**: All cross-system communication via EventBus. No direct references between systems.
- **State machine**: Generic `StateMachine` + `State` classes in `utils/`. Monster uses 5 states: Idle, Patrol, Investigate, Chase, Search.
- **Interactables**: Base class `Interactable extends StaticBody3D` with `interact(player)` pattern. Subclasses: Door, PickupItem, Note, Generator.

## Conventions
- See CONVENTIONS.md for full rules
- Files: snake_case. Nodes: PascalCase. Signals: snake_case past tense.
- Static typing everywhere. `@export`/`@onready` patterns. `StringName` for actions (`&"name"`).
- Physics layers: 1=World, 2=Player, 3=Monsters, 4=Interactables, 5=Triggers, 6=Navigation
- Audio buses: Master, Music, SFX, Ambience, Voice

## Key Paths
- Player: `player/player.tscn` (CharacterBody3D with camera, flashlight, interaction)
- Monster: `enemies/stalker/stalker.tscn` (5-state AI with sight/sound sensors)
- Test level: `levels/test_level/test_level.tscn` (small validation level)
- Town: `levels/town/town.tscn` (full blockout, 12 districts, 200x200)
- Post-processing: `shaders/post_process.tscn` (vignette, aberration, grain, distortion)
- Objectives: `resources/objectives/*.tres` (3 templates: generators, keys, radio)

## Current State
- All foundation code complete (69 files, 5800+ lines)
- Placeholder box meshes — need AI-generated .glb replacements
- No audio files yet — need ElevenLabs SFX + Suno music
- Navigation meshes need baking in editor
- Need testing in Godot editor to validate scene loading
