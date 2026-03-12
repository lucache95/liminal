extends Node
## Tracks hidden sanity state driven by light levels, monster proximity,
## and player actions. Emits sanity_changed to drive visual and audio effects.

# ---------------------------------------------------------------------------
# Exports
# ---------------------------------------------------------------------------

@export var darkness_drain_rate: float = 0.008   ## Per second in total darkness (~125s to zero)
@export var monster_drain_rate: float = 0.015     ## Additional per second near monster
@export var flashlight_restore_rate: float = 0.005 ## Per second with flashlight on
@export var light_restore_rate: float = 0.006     ## Per second near environmental light (~167s full restore)
@export var objective_boost: float = 0.3          ## Instant boost on objective completion

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const DARKNESS_THRESHOLD: float = 0.3  ## Light level below this counts as darkness
const LIGHT_THRESHOLD: float = 0.5     ## Light level above this restores sanity
const ZERO_SANITY_SIGNAL_INTERVAL: float = 2.0  ## Re-emit zero-sanity signal interval

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var sanity: float = 1.0
var last_sampled_light_level: float = 0.5  ## Cached light level for external systems (sight_sensor)
var _player: CharacterBody3D = null
var _flashlight_on: bool = false
var _monster_nearby: bool = false
var _monster_alert_level: float = 0.0
var _ambient_light_level: float = 1.0
var _day_night_cycle: Node = null
var _zero_sanity_timer: float = 0.0

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	EventBus.player_spawned.connect(_on_player_spawned)
	EventBus.flashlight_toggled.connect(_on_flashlight_toggled)
	EventBus.monster_alert_changed.connect(_on_monster_alert_changed)
	EventBus.objective_completed.connect(_on_objective_completed)
	EventBus.game_started.connect(_on_game_started)
	EventBus.day_night_progress.connect(_on_day_night_progress)

	var timer := Timer.new()
	timer.name = "SanityTimer"
	timer.wait_time = 0.25
	timer.autostart = true
	timer.timeout.connect(_update_sanity)
	add_child(timer)

# ---------------------------------------------------------------------------
# Signal callbacks
# ---------------------------------------------------------------------------

func _on_game_started(_seed: int) -> void:
	sanity = 1.0
	_flashlight_on = false
	_monster_nearby = false
	_monster_alert_level = 0.0
	_zero_sanity_timer = 0.0
	EventBus.sanity_changed.emit(sanity)


func _on_player_spawned(player: CharacterBody3D) -> void:
	_player = player


func _on_flashlight_toggled(is_on: bool) -> void:
	_flashlight_on = is_on


func _on_monster_alert_changed(level: float) -> void:
	_monster_alert_level = level
	_monster_nearby = level > 0.3


func _on_objective_completed(_objective_id: String) -> void:
	sanity = clampf(sanity + objective_boost, 0.0, 1.0)
	EventBus.sanity_changed.emit(sanity)


func _on_day_night_progress(_t: float) -> void:
	if _day_night_cycle == null:
		_day_night_cycle = get_tree().get_first_node_in_group(&"day_night_cycle")
	if _day_night_cycle != null:
		_ambient_light_level = _day_night_cycle.ambient_light_level

# ---------------------------------------------------------------------------
# Core update
# ---------------------------------------------------------------------------

## Called every 0.25s by timer. Samples light, applies drain/restore, emits signal.
func _update_sanity() -> void:
	if _player == null or not GameManager.run_active:
		return

	var delta_t: float = 0.25
	var light_level: float = _sample_light_level()
	last_sampled_light_level = light_level

	# Drain in darkness
	if light_level < DARKNESS_THRESHOLD:
		var darkness_factor: float = 1.0 - (light_level / DARKNESS_THRESHOLD)
		sanity -= darkness_drain_rate * delta_t * darkness_factor

	# Additional drain from monster proximity
	if _monster_nearby:
		sanity -= monster_drain_rate * delta_t * _monster_alert_level

	# Restore from flashlight
	if _flashlight_on:
		sanity += flashlight_restore_rate * delta_t

	# Restore from environmental light
	if light_level > LIGHT_THRESHOLD:
		var light_factor: float = (light_level - LIGHT_THRESHOLD) * 2.0
		sanity += light_restore_rate * delta_t * light_factor

	sanity = clampf(sanity, 0.0, 1.0)
	EventBus.sanity_changed.emit(sanity)

	# At zero sanity, periodically attract the monster
	if sanity <= 0.0:
		_zero_sanity_timer += delta_t
		if _zero_sanity_timer >= ZERO_SANITY_SIGNAL_INTERVAL:
			_zero_sanity_timer = 0.0
			EventBus.sound_emitted.emit(_player.global_position, 1.0, "sanity_break")
	else:
		_zero_sanity_timer = 0.0

# ---------------------------------------------------------------------------
# Light sampling
# ---------------------------------------------------------------------------

## Samples the total light level at the player position from all sources.
func _sample_light_level() -> float:
	var total_light: float = _ambient_light_level
	var player_pos: Vector3 = _player.global_position + Vector3.UP * 1.0

	# Environmental light sources (OmniLight3D / SpotLight3D in group)
	for node: Node in get_tree().get_nodes_in_group(&"light_source"):
		if node is OmniLight3D:
			var light: OmniLight3D = node as OmniLight3D
			if not light.visible:
				continue
			var dist: float = player_pos.distance_to(light.global_position)
			if dist < light.omni_range:
				var attenuation: float = pow(1.0 - dist / light.omni_range, light.omni_attenuation)
				total_light += light.light_energy * attenuation
		elif node is SpotLight3D:
			var light: SpotLight3D = node as SpotLight3D
			if not light.visible:
				continue
			var dist: float = player_pos.distance_to(light.global_position)
			if dist < light.spot_range:
				var attenuation: float = pow(1.0 - dist / light.spot_range, light.spot_attenuation)
				total_light += light.light_energy * attenuation * 0.5

	# Flashlight contribution
	if _flashlight_on:
		total_light += 0.4

	# Monster lantern (future-proof)
	for node: Node in get_tree().get_nodes_in_group(&"monster_lantern"):
		if node is OmniLight3D:
			var light: OmniLight3D = node as OmniLight3D
			var dist: float = player_pos.distance_to(light.global_position)
			if dist < light.omni_range:
				var attenuation: float = pow(1.0 - dist / light.omni_range, light.omni_attenuation)
				total_light += light.light_energy * attenuation * 0.3

	return clampf(total_light, 0.0, 1.0)
