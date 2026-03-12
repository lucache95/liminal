class_name Lurker
extends Node3D
## Invisible zone-based monster that creates area-denial through environmental
## disturbance. Roams on NavMesh with a large danger zone; when the player
## enters, nearby lights flicker, sanity drains faster, and after attack_delay
## seconds the player is killed. Effects are WORLD-SPACE (light energy changes)
## not screen-space, distinct from sanity PostProcess effects.

@export var config: LurkerConfig

@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var danger_zone: Area3D = $DangerZone

var _player_in_zone: bool = false
var _zone_timer: float = 0.0
var _roaming: bool = true
var _roam_wait_timer: float = 0.0
var _roam_waiting: bool = false

## Stores original light energies so they can be restored on zone exit.
var _original_light_energies: Dictionary = {}


func _ready() -> void:
	add_to_group(&"monster")

	danger_zone.body_entered.connect(_on_danger_zone_entered)
	danger_zone.body_exited.connect(_on_danger_zone_exited)

	config = preload("res://resources/enemy_configs/lurker_config.tres")

	var audio_controller: LurkerAudio = LurkerAudio.new()
	audio_controller.name = "LurkerAudio"
	add_child(audio_controller)

	_pick_roam_target()


func _physics_process(delta: float) -> void:
	_roam(delta)

	if _player_in_zone:
		_zone_timer += delta
		var intensity: float = clampf(_zone_timer / config.attack_delay, 0.0, 1.0)
		_update_disturbances(intensity)
		_drain_sanity(intensity)
		if _zone_timer >= config.attack_delay:
			EventBus.player_died.emit()


func _roam(delta: float) -> void:
	if _roam_waiting:
		_roam_wait_timer += delta
		if _roam_wait_timer >= randf_range(config.roam_wait_min, config.roam_wait_max):
			_roam_waiting = false
			_pick_roam_target()
		return

	if nav_agent.is_navigation_finished():
		_roam_waiting = true
		_roam_wait_timer = 0.0
		return

	var next_pos: Vector3 = nav_agent.get_next_path_position()
	var direction: Vector3 = (next_pos - global_position).normalized()
	global_position += direction * config.roam_speed * delta


func _pick_roam_target() -> void:
	var target := Vector3(
		randf_range(-config.roam_range, config.roam_range),
		0.0,
		randf_range(-config.roam_range, config.roam_range),
	)
	var nav_map: RID = get_world_3d().navigation_map
	target = NavigationServer3D.map_get_closest_point(nav_map, target)
	nav_agent.target_position = target


func _on_danger_zone_entered(body: Node3D) -> void:
	if body.is_in_group(&"player"):
		_player_in_zone = true
		_zone_timer = 0.0
		EventBus.lurker_zone_entered.emit()


func _on_danger_zone_exited(body: Node3D) -> void:
	if body.is_in_group(&"player"):
		_player_in_zone = false
		_zone_timer = 0.0
		_restore_disturbances()
		EventBus.lurker_zone_exited.emit()


func _update_disturbances(intensity: float) -> void:
	## Flicker nearby lights in the "light_source" group within disturbance radius.
	## Effects are world-space (OmniLight3D energy) not screen-space (PostProcess).
	for node: Node in get_tree().get_nodes_in_group(&"light_source"):
		if node is OmniLight3D:
			var light: OmniLight3D = node as OmniLight3D
			var dist: float = global_position.distance_to(light.global_position)
			if dist <= config.disturbance_radius:
				if not _original_light_energies.has(light):
					_original_light_energies[light] = light.light_energy
				var original_energy: float = _original_light_energies[light]
				light.light_energy = original_energy * randf_range(0.2, 1.0) * lerpf(1.0, 0.3, intensity)


func _drain_sanity(intensity: float) -> void:
	## Emit escalating monster alert so SanityManager applies increased drain.
	EventBus.monster_alert_changed.emit(intensity)


func _restore_disturbances() -> void:
	## Restore all flickered lights to their original energy values.
	for light: OmniLight3D in _original_light_energies.keys():
		if is_instance_valid(light):
			light.light_energy = _original_light_energies[light]
	_original_light_energies.clear()
	EventBus.monster_alert_changed.emit(0.0)
