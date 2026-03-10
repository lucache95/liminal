# Project Conventions — All Agents Must Follow

## Game: "Liminal" — First-Person Horror/Exploration

### Godot Version: 4.4, Forward+ Renderer

## File Conventions
- All file/folder names: snake_case
- All node names in scenes: PascalCase
- GDScript class names: PascalCase
- Signals: snake_case (past tense: item_picked_up, door_opened)
- Constants: UPPER_SNAKE_CASE
- Variables/functions: snake_case

## GDScript Style
- Use static typing everywhere: `var speed: float = 5.0`
- Use `@export` for inspector-exposed vars
- Use `@onready` for node references
- Signal declarations at top of file, then exports, then vars, then onready
- Use `StringName` for signal names and input actions
- Prefer `push_error()` over `print()` for errors
- Group physics in `_physics_process`, visuals in `_process`

## Scene File (.tscn) Rules
- format=3 (Godot 4.x)
- Use `uid://` references where possible
- External resources use `[ext_resource]` with string IDs like `"1_abc12"`
- Sub-resources use `[sub_resource]` with type-based IDs
- Root node name matches the scene purpose (Player, Monster, MainMenu, etc.)

## Autoload Singletons (registered in project.godot)
- GameManager — game state, pause, seed, current run data
- AudioManager — music/SFX bus control, ambient layers
- SceneManager — scene transitions, loading
- EventBus — global signal bus for decoupled communication

## Input Actions (defined in project.godot)
- move_forward, move_backward, move_left, move_right
- sprint, crouch
- interact (E key)
- flashlight_toggle (F key)
- pause (Escape)

## Signal Bus Pattern
All cross-system communication goes through EventBus autoload:
```gdscript
# EventBus.gd
signal player_died
signal item_picked_up(item_id: String)
signal objective_completed(objective_id: String)
signal monster_alert_changed(level: float)
signal flashlight_toggled(is_on: bool)
signal game_started(seed: int)
signal game_ended(reason: String)
signal tension_changed(value: float)
```

## Node Path Assumptions
- Player camera is at: Player/Head/Camera3D
- Player position = CharacterBody3D.global_position
- Monster accesses player via: get_tree().get_first_node_in_group("player")
- All interactable objects are in group "interactable"
- All monsters are in group "monster"
- Spawn points are Marker3D nodes in group "spawn_point"

## Physics Layers
- Layer 1: World geometry (walls, floors, buildings)
- Layer 2: Player
- Layer 3: Monsters
- Layer 4: Interactables
- Layer 5: Triggers/zones (Area3D)
- Layer 6: Navigation obstacles

## Audio Buses
- Master
- Music (parent: Master)
- SFX (parent: Master)
- Ambience (parent: Master)
- Voice (parent: Master)

## Resource Paths
- Models: res://assets/models/{category}/{name}.glb
- Textures: res://assets/textures/{category}/{name}_{map}.png
- Audio SFX: res://assets/audio/sfx/{name}.ogg
- Audio Music: res://assets/audio/music/{name}.ogg
- Audio Ambience: res://assets/audio/ambience/{name}.ogg
