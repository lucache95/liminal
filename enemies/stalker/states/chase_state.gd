extends State
## Chase state: full-speed pursuit of the player.
## Updates nav target frequently. Kills on contact. Transitions to search on losing sight.

const NAV_UPDATE_INTERVAL: float = 0.3
const KILL_DISTANCE: float = 1.5
const LOSE_SIGHT_TIMEOUT: float = 10.0
const TENSION_UPDATE_INTERVAL: float = 0.5
const MAX_CHASE_DISTANCE: float = 60.0

var _nav_update_timer: float = 0.0
var _time_since_player_seen: float = 0.0
var _tension_timer: float = 0.0
var _stalker: CharacterBody3D


func enter(data: Dictionary) -> void:
	_stalker = get_parent().get_parent() as CharacterBody3D
	_nav_update_timer = 0.0
	_time_since_player_seen = 0.0
	_tension_timer = 0.0

	# Max alert
	_stalker.blackboard["alert_level"] = 1.0
	EventBus.emit_signal("monster_alert_changed", 1.0)
	EventBus.emit_signal("tension_changed", 0.9)

	# Play jumpscare sting on chase start
	var sting_path: String = "res://assets/audio/sfx/jumpscare_sting.mp3"
	if ResourceLoader.exists(sting_path):
		var sting: AudioStream = load(sting_path)
		AudioManager.play_stinger(sting)

	# Set initial target from data or blackboard
	var target_pos: Vector3 = data.get(
		"last_known_position",
		_stalker.blackboard.get("last_known_position", _stalker.global_position)
	)
	_stalker.blackboard["last_known_position"] = target_pos
	_stalker.move_to_point(target_pos)


func physics_update(delta: float) -> void:
	_nav_update_timer += delta
	_tension_timer += delta

	var player: Node3D = _stalker.get_player()
	if player == null or not is_instance_valid(player):
		# Player gone — transition to search
		state_machine.transition_to("searchstate", {
			"last_known_position": _stalker.blackboard["last_known_position"],
		})
		return

	var player_pos: Vector3 = player.global_position
	var monster_pos: Vector3 = _stalker.global_position
	var distance: float = monster_pos.distance_to(player_pos)

	# Check for kill distance
	if distance <= KILL_DISTANCE:
		EventBus.emit_signal("player_died")
		# Stay in chase state — game over handling is external
		return

	# Track line of sight
	if _stalker.blackboard.get("player_visible", false):
		_time_since_player_seen = 0.0
		_stalker.blackboard["last_known_position"] = player_pos
		_stalker.blackboard["time_since_player_seen"] = 0.0
	else:
		_time_since_player_seen += delta
		_stalker.blackboard["time_since_player_seen"] = _time_since_player_seen

	# Update navigation target periodically
	if _nav_update_timer >= NAV_UPDATE_INTERVAL:
		_nav_update_timer = 0.0
		if _time_since_player_seen < 2.0:
			# Still have recent sighting — chase directly
			_stalker.move_to_point(player_pos)
		else:
			# Lost sight — head to last known position
			_stalker.move_to_point(_stalker.blackboard["last_known_position"])

	# Update tension based on distance
	if _tension_timer >= TENSION_UPDATE_INTERVAL:
		_tension_timer = 0.0
		var tension: float = _calculate_tension(distance)
		EventBus.emit_signal("tension_changed", tension)

	# Lost sight for too long — transition to search
	if _time_since_player_seen >= LOSE_SIGHT_TIMEOUT:
		state_machine.transition_to("searchstate", {
			"last_known_position": _stalker.blackboard["last_known_position"],
		})
		return

	# If player has gotten very far away, switch to search to avoid infinite running
	if distance > MAX_CHASE_DISTANCE and _time_since_player_seen > 3.0:
		state_machine.transition_to("searchstate", {
			"last_known_position": _stalker.blackboard["last_known_position"],
		})


func exit() -> void:
	_nav_update_timer = 0.0
	_time_since_player_seen = 0.0


## Returns tension value (0.7 to 1.0) based on distance to player.
func _calculate_tension(distance: float) -> float:
	# Close = 1.0, far = 0.7, clamped
	var normalized_dist: float = clampf(distance / 30.0, 0.0, 1.0)
	return lerpf(1.0, 0.7, normalized_dist)
