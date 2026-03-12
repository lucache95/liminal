extends State
## Patrol state: walks between patrol points, waits briefly at each.
## Listens for sounds and periodically checks sight.

const WAIT_TIME_MIN: float = 3.0
const WAIT_TIME_MAX: float = 8.0
const SIGHT_CHECK_INTERVAL: float = 0.2
const ALERT_SIGHT_THRESHOLD: float = 0.4

var _current_point_index: int = 0
var _waiting: bool = false
var _wait_timer: float = 0.0
var _wait_duration: float = 0.0
var _sight_check_timer: float = 0.0
var _stalker: CharacterBody3D


func enter(_data: Dictionary) -> void:
	_stalker = get_parent().get_parent() as CharacterBody3D
	_waiting = false
	_wait_timer = 0.0
	_sight_check_timer = 0.0

	# Pick the nearest patrol point to start from
	_current_point_index = _find_nearest_patrol_point()
	_navigate_to_current_point()


func physics_update(delta: float) -> void:
	_sight_check_timer += delta

	# Check for sounds
	var hearing: Node3D = _stalker.hearing_sensor
	if hearing.has_method(&"get_latest_sound"):
		var sound: Dictionary = hearing.call(&"get_latest_sound")
		if not sound.is_empty():
			hearing.call(&"clear_sounds")
			state_machine.transition_to("investigatestate", {
				"last_known_position": sound["position"],
				"reason": "sound",
			})
			return

	# Periodic sight check
	if _sight_check_timer >= SIGHT_CHECK_INTERVAL:
		_sight_check_timer = 0.0
		if _stalker.blackboard.get("player_visible", false):
			var player: Node3D = _stalker.get_player()
			if player:
				var distance: float = _stalker.global_position.distance_to(player.global_position)
				var angle_deg: float = rad_to_deg(
					_stalker.get_forward_direction().angle_to(
						(player.global_position - _stalker.global_position).normalized()
					)
				)
				var strength: float = _stalker.sight_sensor.get_detection_strength(
					distance, angle_deg, _stalker.config
				)

				# Update alert level
				_stalker.blackboard["alert_level"] = clampf(
					_stalker.blackboard.get("alert_level", 0.0) + _stalker.config.alert_buildup_rate * delta * strength * 5.0,
					0.0, 1.0
				)
				EventBus.emit_signal("monster_alert_changed", _stalker.blackboard["alert_level"])

				if _stalker.blackboard["alert_level"] >= ALERT_SIGHT_THRESHOLD:
					state_machine.transition_to("investigatestate", {
						"last_known_position": _stalker.blackboard["last_known_position"],
						"reason": "sight",
					})
					return
		else:
			# Decay alert when player is not visible
			_stalker.blackboard["alert_level"] = clampf(
				_stalker.blackboard.get("alert_level", 0.0) - _stalker.config.alert_decay_rate * delta,
				0.0, 1.0
			)

	# Handle waiting at patrol point
	if _waiting:
		_wait_timer += delta
		if _wait_timer >= _wait_duration:
			_waiting = false
			_advance_patrol_point()
			_navigate_to_current_point()
		return

	# Check if arrived at patrol point
	if _stalker.has_reached_target():
		_waiting = true
		_wait_timer = 0.0
		_wait_duration = randf_range(WAIT_TIME_MIN, WAIT_TIME_MAX)


func exit() -> void:
	_waiting = false
	_wait_timer = 0.0


func _navigate_to_current_point() -> void:
	var points: Array[Marker3D] = _stalker.patrol_points
	if points.is_empty():
		# No patrol points — wander randomly nearby
		var random_offset: Vector3 = Vector3(
			randf_range(-10.0, 10.0),
			0.0,
			randf_range(-10.0, 10.0)
		)
		_stalker.move_to_point(_stalker.global_position + random_offset)
		return

	var target_point: Marker3D = points[_current_point_index]
	_stalker.move_to_point(target_point.global_position)


func _advance_patrol_point() -> void:
	var points: Array[Marker3D] = _stalker.patrol_points
	if points.is_empty():
		return
	_current_point_index = (_current_point_index + 1) % points.size()


func _find_nearest_patrol_point() -> int:
	var points: Array[Marker3D] = _stalker.patrol_points
	if points.is_empty():
		return 0

	var nearest_index: int = 0
	var nearest_dist: float = INF
	var monster_pos: Vector3 = _stalker.global_position

	for i: int in range(points.size()):
		var dist: float = monster_pos.distance_to(points[i].global_position)
		if dist < nearest_dist:
			nearest_dist = dist
			nearest_index = i

	return nearest_index
