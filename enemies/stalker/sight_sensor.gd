extends Node3D
## Handles vision-based detection of the player.
## Uses distance, angle, light level, and line-of-sight checks.

const RAYCAST_LENGTH: float = 100.0


## Returns true if the monster can see the player given all conditions.
func can_see_player(monster_pos: Vector3, monster_forward: Vector3, player: Node3D, config: MonsterConfig) -> bool:
	if player == null:
		return false

	var player_pos: Vector3 = player.global_position
	var to_player: Vector3 = player_pos - monster_pos
	var distance: float = to_player.length()

	# Calculate effective sight range based on light level
	var light_level: float = _sample_player_light_level(player)
	var effective_range: float = config.sight_range

	# Darkness reduces sight range: at light_level=0 monster sees at 40% range
	# At light_level=0.5+ monster sees at full range
	var light_factor: float = clampf(light_level / 0.5, 0.4, 1.0)
	effective_range *= light_factor

	# Flashlight beacon: player is more visible when flashlight is on (+50% range)
	var flashlight_node: Node = player.find_child("Flashlight", true, false)
	if flashlight_node and flashlight_node is Light3D and (flashlight_node as Light3D).visible:
		effective_range *= 1.5

	# Check 1: Distance within effective sight range
	if distance > effective_range:
		return false

	# Check 2: Angle within sight cone (half-angle check)
	var direction_to_player: Vector3 = to_player.normalized()
	var angle_rad: float = monster_forward.angle_to(direction_to_player)
	var half_sight_angle_rad: float = deg_to_rad(config.sight_angle_degrees / 2.0)
	if angle_rad > half_sight_angle_rad:
		return false

	# Check 3: Light level at player position above threshold
	if light_level < config.light_threshold:
		return false

	# Check 4: Line of sight — no obstacles between monster and player
	if not _has_line_of_sight(monster_pos, player_pos):
		return false

	return true


## Returns a detection strength from 0.0 to 1.0 based on distance and angle.
## Closer and more centered = stronger detection.
func get_detection_strength(distance: float, angle_deg: float, config: MonsterConfig) -> float:
	if distance > config.sight_range:
		return 0.0

	var half_angle: float = config.sight_angle_degrees / 2.0
	if angle_deg > half_angle:
		return 0.0

	# Distance factor: 1.0 at distance=0, 0.0 at sight_range
	var distance_factor: float = 1.0 - clampf(distance / config.sight_range, 0.0, 1.0)

	# Angle factor: 1.0 when directly ahead, 0.0 at edge of sight cone
	var angle_factor: float = 1.0 - clampf(angle_deg / half_angle, 0.0, 1.0)

	# Combined strength — weight distance more heavily than angle
	return clampf(distance_factor * 0.7 + angle_factor * 0.3, 0.0, 1.0)


## Samples the light level at the player's position.
## Uses the player's method if available, otherwise returns a default based on environment.
func _sample_player_light_level(player: Node3D) -> float:
	# If the player exposes a light sampling method, use it
	if player.has_method(&"get_light_exposure"):
		return player.call(&"get_light_exposure") as float

	# Fallback: check if the player's flashlight is on (always visible)
	# or use a default ambient light value
	var flashlight_node: Node = player.find_child("Flashlight", true, false)
	if flashlight_node and flashlight_node is Light3D:
		if (flashlight_node as Light3D).visible:
			return 1.0

	# Default ambient light — moderately dark environment
	return 0.15


## Performs a physics raycast to check line of sight between two points.
## Returns true if nothing blocks the view (only checks world geometry layer 1).
func _has_line_of_sight(from_pos: Vector3, to_pos: Vector3) -> bool:
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	if space_state == null:
		return false

	# Offset origin slightly upward to cast from "eye" height
	var eye_offset: Vector3 = Vector3.UP * 1.6
	var from: Vector3 = from_pos + eye_offset
	# Target the player's upper body (not feet)
	var to: Vector3 = to_pos + Vector3.UP * 1.2

	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to)
	# Only check against world geometry (layer 1)
	query.collision_mask = 1
	query.collide_with_areas = false

	var result: Dictionary = space_state.intersect_ray(query)
	# If no hit, line of sight is clear
	return result.is_empty()
