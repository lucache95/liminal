class_name AIDirector
extends Node
## Left 4 Dead-style encounter pacing for Stalker runs.
## Manages a 4-state cycle: CALM -> BUILD_UP -> ENCOUNTER -> RETREAT.
## Escalates pressure as night deepens via day_night_progress signal.

enum DirectorState { CALM, BUILD_UP, ENCOUNTER, RETREAT }

## Maximum retreat duration at start of night (seconds).
@export var retreat_duration_max: float = 120.0
## Minimum retreat duration at full night (seconds).
@export var retreat_duration_min: float = 45.0
## Day/night progress threshold to transition from CALM to BUILD_UP.
@export var buildup_threshold: float = 0.15
## Day/night progress threshold for first encounter if none triggered naturally.
@export var first_encounter_threshold: float = 0.30

var state: DirectorState = DirectorState.CALM
var _stalker: CharacterBody3D = null
var _retreat_timer: float = 0.0
var _retreat_duration: float = 90.0
var _day_night_t: float = 0.0
var _encounter_count: int = 0


func _ready() -> void:
	EventBus.day_night_progress.connect(_on_day_night_progress)
	EventBus.monster_state_changed.connect(_on_monster_state_changed)
	call_deferred("_find_stalker")


func _find_stalker() -> void:
	_stalker = get_tree().get_first_node_in_group(&"monster")
	if _stalker == null:
		push_warning("AIDirector: No monster found in 'monster' group")


func _physics_process(delta: float) -> void:
	if _stalker == null or not is_instance_valid(_stalker):
		_find_stalker()
		return

	# Only tick the retreat timer when in RETREAT state
	if state == DirectorState.RETREAT:
		_retreat_timer += delta
		if _retreat_timer >= _retreat_duration:
			_transition_to(DirectorState.BUILD_UP)


func _on_day_night_progress(t: float) -> void:
	_day_night_t = t

	# Escalate: shorter retreats as night deepens
	_retreat_duration = lerpf(retreat_duration_max, retreat_duration_min, t)

	match state:
		DirectorState.CALM:
			if t >= buildup_threshold:
				_transition_to(DirectorState.BUILD_UP)
		DirectorState.BUILD_UP:
			if t >= first_encounter_threshold and _encounter_count == 0:
				_transition_to(DirectorState.ENCOUNTER)


func _on_monster_state_changed(new_state: String) -> void:
	match state:
		DirectorState.BUILD_UP:
			if new_state.to_lower() == "chasestate":
				# Monster found the player naturally during buildup
				_transition_to(DirectorState.ENCOUNTER)
		DirectorState.ENCOUNTER:
			if new_state.to_lower() == "patrolstate":
				# Monster lost the player -- trigger retreat for safe window
				_force_retreat()


func _transition_to(new_state: DirectorState) -> void:
	state = new_state
	EventBus.director_state_changed.emit(DirectorState.keys()[state])

	match new_state:
		DirectorState.CALM:
			# Reduce hearing awareness during calm periods
			if _stalker and is_instance_valid(_stalker) and _stalker.config:
				var hearing: Node3D = _stalker.hearing_sensor
				if hearing and hearing.has_method(&"set_range_override"):
					hearing.call(&"set_range_override", _stalker.config.hearing_range * 0.5)
		DirectorState.BUILD_UP:
			# Restore full hearing awareness
			if _stalker and is_instance_valid(_stalker) and _stalker.config:
				var hearing: Node3D = _stalker.hearing_sensor
				if hearing and hearing.has_method(&"set_range_override"):
					hearing.call(&"set_range_override", _stalker.config.hearing_range)
		DirectorState.ENCOUNTER:
			_encounter_count += 1
		DirectorState.RETREAT:
			_force_retreat()


func _force_retreat() -> void:
	if _stalker == null or not is_instance_valid(_stalker):
		return

	# Find the player to calculate farthest retreat point
	var player: Node3D = get_tree().get_first_node_in_group(&"player")
	var retreat_points: Array[Node] = get_tree().get_nodes_in_group(&"retreat_point")

	if retreat_points.is_empty():
		push_warning("AIDirector: No retreat points found in 'retreat_point' group")
		return

	# Select the retreat point farthest from the player
	var best_point: Vector3 = Vector3.ZERO
	var best_distance: float = -1.0
	var reference_pos: Vector3 = player.global_position if player else _stalker.global_position

	for point: Node in retreat_points:
		if point is Node3D:
			var dist: float = reference_pos.distance_to((point as Node3D).global_position)
			if dist > best_distance:
				best_distance = dist
				best_point = (point as Node3D).global_position

	# Navigate monster to retreat point
	_stalker.move_to_point(best_point)

	# Force back to patrol state
	if _stalker.state_machine:
		_stalker.state_machine.transition_to("patrolstate")

	# Reset alert and tension
	_stalker.blackboard["alert_level"] = 0.0
	EventBus.monster_alert_changed.emit(0.0)
	EventBus.tension_changed.emit(0.0)

	# Reset retreat timer
	_retreat_timer = 0.0

	# Ensure state is RETREAT
	if state != DirectorState.RETREAT:
		state = DirectorState.RETREAT
		EventBus.director_state_changed.emit(DirectorState.keys()[state])
