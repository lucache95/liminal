extends State
## Investigate state: moves to last known position, looks around.
## Transitions to chase if player found, patrol if nothing after timeout.

const LOOK_AROUND_DURATION: float = 4.0
const LOOK_ROTATE_SPEED: float = 1.2
const SIGHT_CHECK_INTERVAL: float = 0.15
const ALERT_CHASE_THRESHOLD: float = 0.8

var _target_position: Vector3 = Vector3.ZERO
var _arrived: bool = false
var _look_timer: float = 0.0
var _total_timer: float = 0.0
var _sight_check_timer: float = 0.0
var _look_direction: float = 1.0  # 1.0 or -1.0 for rotation direction
var _stalker: CharacterBody3D


func enter(data: Dictionary) -> void:
	_stalker = get_parent().get_parent() as CharacterBody3D
	_target_position = data.get("last_known_position", _stalker.blackboard.get("last_known_position", _stalker.global_position))
	_arrived = false
	_look_timer = 0.0
	_total_timer = 0.0
	_sight_check_timer = 0.0
	_look_direction = 1.0 if randf() > 0.5 else -1.0

	# Store position in blackboard
	_stalker.blackboard["last_known_position"] = _target_position

	# Navigate to the position of interest
	_stalker.move_to_point(_target_position)

	# Raise alert slightly on entering investigate
	_stalker.blackboard["alert_level"] = clampf(
		_stalker.blackboard.get("alert_level", 0.0) + 0.1,
		0.0, 1.0
	)
	EventBus.emit_signal("monster_alert_changed", _stalker.blackboard["alert_level"])
	EventBus.emit_signal("tension_changed", clampf(_stalker.blackboard["alert_level"] * 0.6, 0.0, 0.6))


func physics_update(delta: float) -> void:
	_total_timer += delta
	_sight_check_timer += delta

	# Check for new sounds — update target if a louder sound is heard
	var hearing: Node3D = _stalker.hearing_sensor
	if hearing.has_method(&"get_latest_sound"):
		var sound: Dictionary = hearing.call(&"get_latest_sound")
		if not sound.is_empty() and sound.get("intensity", 0.0) > 0.3:
			_target_position = sound["position"]
			_stalker.blackboard["last_known_position"] = _target_position
			_stalker.move_to_point(_target_position)
			_arrived = false
			_look_timer = 0.0
			hearing.call(&"clear_sounds")

	# Periodic sight check
	if _sight_check_timer >= SIGHT_CHECK_INTERVAL:
		_sight_check_timer = 0.0
		if _stalker.blackboard.get("player_visible", false):
			# Build up alert rapidly during investigation
			_stalker.blackboard["alert_level"] = clampf(
				_stalker.blackboard.get("alert_level", 0.0) + _stalker.config.alert_buildup_rate * delta * 10.0,
				0.0, 1.0
			)
			EventBus.emit_signal("monster_alert_changed", _stalker.blackboard["alert_level"])

			if _stalker.blackboard["alert_level"] >= ALERT_CHASE_THRESHOLD:
				state_machine.transition_to("chasestate", {
					"last_known_position": _stalker.blackboard["last_known_position"],
				})
				return

	# Handle arrival and look-around behavior
	if not _arrived:
		if _stalker.has_reached_target():
			_arrived = true
			_look_timer = 0.0
	else:
		_look_timer += delta
		# Rotate slowly to look around
		_rotate_look_around(delta)

		if _look_timer >= LOOK_AROUND_DURATION:
			# Done looking, nothing found
			if _total_timer >= _stalker.config.lose_interest_time:
				_lose_interest()
				return
			# Pick a nearby random spot to check
			_pick_nearby_spot()
			_arrived = false

	# Overall timeout
	if _total_timer >= _stalker.config.lose_interest_time:
		_lose_interest()


func exit() -> void:
	_total_timer = 0.0
	_look_timer = 0.0


func _rotate_look_around(delta: float) -> void:
	# Oscillate rotation direction
	if _look_timer > LOOK_AROUND_DURATION * 0.5:
		_look_direction = -_look_direction if _look_direction > 0.0 else _look_direction
	_stalker.rotate_y(_look_direction * LOOK_ROTATE_SPEED * delta)


func _pick_nearby_spot() -> void:
	var offset: Vector3 = Vector3(
		randf_range(-6.0, 6.0),
		0.0,
		randf_range(-6.0, 6.0)
	)
	var new_target: Vector3 = _target_position + offset
	_stalker.move_to_point(new_target)


func _lose_interest() -> void:
	_stalker.blackboard["alert_level"] = clampf(
		_stalker.blackboard.get("alert_level", 0.0) - 0.2,
		0.0, 1.0
	)
	EventBus.emit_signal("monster_alert_changed", _stalker.blackboard["alert_level"])
	EventBus.emit_signal("tension_changed", 0.2)
	state_machine.transition_to("patrolstate")
