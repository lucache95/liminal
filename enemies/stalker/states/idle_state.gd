extends State
## Idle state: monster stands still for a random duration, then transitions to patrol.
## If an alert is triggered (sight or sound), transitions to investigate.

const IDLE_TIME_MIN: float = 10.0
const IDLE_TIME_MAX: float = 30.0
const SIGHT_CHECK_INTERVAL: float = 0.2

var _idle_timer: float = 0.0
var _idle_duration: float = 0.0
var _sight_check_timer: float = 0.0
var _stalker: CharacterBody3D


func enter(_data: Dictionary) -> void:
	_stalker = get_parent().get_parent() as CharacterBody3D
	_idle_duration = randf_range(IDLE_TIME_MIN, IDLE_TIME_MAX)
	_idle_timer = 0.0
	_sight_check_timer = 0.0


func physics_update(delta: float) -> void:
	_idle_timer += delta
	_sight_check_timer += delta

	# Check for sounds from hearing sensor
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
			state_machine.transition_to("investigatestate", {
				"last_known_position": _stalker.blackboard["last_known_position"],
				"reason": "sight",
			})
			return

	# Duration elapsed — transition to patrol
	if _idle_timer >= _idle_duration:
		state_machine.transition_to("patrolstate")


func exit() -> void:
	_idle_timer = 0.0
