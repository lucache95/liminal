extends State
## Search state: after losing the player during chase, searches the area.
## Visits several nearby points, checks sight/sound. Returns to patrol on timeout.

const NUM_SEARCH_POINTS: int = 5
const SEARCH_RADIUS: float = 12.0
const SIGHT_CHECK_INTERVAL: float = 0.15
const TENSION_DECAY_INTERVAL: float = 2.0
const WAIT_AT_POINT_MIN: float = 1.5
const WAIT_AT_POINT_MAX: float = 3.0

var _search_timer: float = 0.0
var _sight_check_timer: float = 0.0
var _tension_timer: float = 0.0
var _search_points: Array[Vector3] = []
var _current_search_index: int = 0
var _waiting_at_point: bool = false
var _wait_timer: float = 0.0
var _wait_duration: float = 0.0
var _search_center: Vector3 = Vector3.ZERO
var _stalker: CharacterBody3D


func enter(data: Dictionary) -> void:
	_stalker = get_parent().get_parent() as CharacterBody3D
	_search_timer = 0.0
	_sight_check_timer = 0.0
	_tension_timer = 0.0
	_current_search_index = 0
	_waiting_at_point = false
	_wait_timer = 0.0

	_search_center = data.get(
		"last_known_position",
		_stalker.blackboard.get("last_known_position", _stalker.global_position)
	)
	_stalker.blackboard["last_known_position"] = _search_center

	# Generate random search points around the last known position
	_generate_search_points()

	# Start tension at moderate level
	EventBus.tension_changed.emit(0.5)

	# Navigate to first search point
	if not _search_points.is_empty():
		_stalker.move_to_point(_search_points[0])


func physics_update(delta: float) -> void:
	_search_timer += delta
	_sight_check_timer += delta
	_tension_timer += delta

	# Check for sounds
	var hearing: Node3D = _stalker.hearing_sensor
	if hearing.has_method(&"get_latest_sound"):
		var sound: Dictionary = hearing.call(&"get_latest_sound")
		if not sound.is_empty() and sound.get("intensity", 0.0) > 0.2:
			hearing.call(&"clear_sounds")
			# Re-center the search on the new sound
			_search_center = sound["position"]
			_stalker.blackboard["last_known_position"] = _search_center
			_generate_search_points()
			_current_search_index = 0
			_waiting_at_point = false
			_stalker.move_to_point(_search_points[0])
			_search_timer = 0.0  # Reset search timer on new lead

	# Periodic sight check
	if _sight_check_timer >= SIGHT_CHECK_INTERVAL:
		_sight_check_timer = 0.0
		if _stalker.blackboard.get("player_visible", false):
			_stalker.blackboard["alert_level"] = 1.0
			EventBus.monster_alert_changed.emit(1.0)
			state_machine.transition_to("chasestate", {
				"last_known_position": _stalker.blackboard["last_known_position"],
			})
			return

	# Gradually reduce tension
	if _tension_timer >= TENSION_DECAY_INTERVAL:
		_tension_timer = 0.0
		var progress: float = clampf(_search_timer / _stalker.config.search_duration, 0.0, 1.0)
		var tension: float = lerpf(0.5, 0.1, progress)
		EventBus.tension_changed.emit(tension)

		# Also decay alert level
		_stalker.blackboard["alert_level"] = clampf(
			_stalker.blackboard.get("alert_level", 0.0) - _stalker.config.alert_decay_rate * TENSION_DECAY_INTERVAL,
			0.0, 1.0
		)
		EventBus.monster_alert_changed.emit(_stalker.blackboard["alert_level"])

	# Search duration expired — give up
	if _search_timer >= _stalker.config.search_duration:
		_give_up()
		return

	# Handle movement between search points
	if _waiting_at_point:
		_wait_timer += delta
		# Look around while waiting
		_stalker.rotate_y(1.5 * delta)
		if _wait_timer >= _wait_duration:
			_waiting_at_point = false
			_advance_to_next_point()
	elif _stalker.has_reached_target():
		_waiting_at_point = true
		_wait_timer = 0.0
		_wait_duration = randf_range(WAIT_AT_POINT_MIN, WAIT_AT_POINT_MAX)


func exit() -> void:
	_search_timer = 0.0
	_search_points.clear()


func _generate_search_points() -> void:
	_search_points.clear()

	# First point is always the search center itself
	_search_points.append(_search_center)

	# Generate additional random points around the center
	for i: int in range(NUM_SEARCH_POINTS - 1):
		var angle: float = randf() * TAU
		var radius: float = randf_range(3.0, SEARCH_RADIUS)
		var offset: Vector3 = Vector3(
			cos(angle) * radius,
			0.0,
			sin(angle) * radius
		)
		_search_points.append(_search_center + offset)


func _advance_to_next_point() -> void:
	_current_search_index += 1
	if _current_search_index >= _search_points.size():
		# All points visited — regenerate or give up
		if _search_timer < _stalker.config.search_duration * 0.7:
			_generate_search_points()
			_current_search_index = 0
			_stalker.move_to_point(_search_points[0])
		else:
			_give_up()
		return

	_stalker.move_to_point(_search_points[_current_search_index])


func _give_up() -> void:
	_stalker.blackboard["alert_level"] = 0.0
	EventBus.monster_alert_changed.emit(0.0)
	EventBus.tension_changed.emit(0.1)
	state_machine.transition_to("patrolstate")
