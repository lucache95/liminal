extends Node
## Global signal bus for decoupled cross-system communication.
## All cross-system signals are declared here. No logic — pure signal relay.

# Player signals
signal player_died
signal player_spawned(player: CharacterBody3D)

# Item / objective signals
signal item_picked_up(item_id: String)
signal objective_completed(objective_id: String)
signal all_objectives_completed

# Monster signals
signal monster_alert_changed(level: float)
signal monster_state_changed(new_state: String)

# Equipment signals
signal flashlight_toggled(is_on: bool)

# Game flow signals
signal game_started(seed: int)
signal game_ended(reason: String) # "escape" or "caught" or "time"

# Atmosphere signals
signal tension_changed(value: float) # 0.0 – 1.0
signal weather_set(weather_type: String)
signal geometry_shifted(node_path: NodePath)

# UI signals
signal interaction_prompt_show(text: String)
signal interaction_prompt_hide

# Spatial audio signal
signal sound_emitted(position: Vector3, intensity: float, source: String)
