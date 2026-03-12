class_name Ambusher
extends Node3D
## Ambusher monster type. Spawns 5-8 invisible kill zones at seed-deterministic NavMesh
## positions. Does NOT join 'monster' group -- no heartbeat proximity audio.
## The silence is the horror.

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const ZONE_COUNT_MIN: int = 5
const ZONE_COUNT_MAX: int = 8
const MIN_ZONE_SPACING: float = 25.0      ## Minimum distance between zones
const MAX_SNAP_DISTANCE: float = 10.0     ## Reject NavMesh snap if too far
const TOWN_HALF_SIZE: float = 90.0        ## Town is 200x200, use +-90 for margin
const WARNING_RADIUS: float = 7.0         ## Radius around zone center for warning props
const SEED_HASH: int = 0x414D4253         ## "AMBS" XOR hash for seed decorrelation
const SPAWN_EXCLUSION_RADIUS: float = 20.0  ## Protect player spawn area

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var _kill_zone_scene: PackedScene

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	# Do NOT add_to_group(&"monster") -- Ambusher is static traps.
	# Heartbeat proximity audio would give false location info. Silence IS the horror cue.
	_kill_zone_scene = preload("res://enemies/ambusher/kill_zone.tscn")
	call_deferred("_spawn_kill_zones")  # Defer so NavMesh is ready


func _spawn_kill_zones() -> void:
	var positions: Array[Vector3] = _generate_zone_positions(GameManager.current_seed)
	for pos: Vector3 in positions:
		var kill_zone: KillZone = _kill_zone_scene.instantiate()
		kill_zone.global_position = pos
		add_child(kill_zone)
		_place_warning_props(pos)

# ---------------------------------------------------------------------------
# Zone position generation (seed-deterministic)
# ---------------------------------------------------------------------------

func _generate_zone_positions(run_seed: int) -> Array[Vector3]:
	var rng := RandomNumberGenerator.new()
	rng.seed = run_seed ^ SEED_HASH  # Decorrelate from weather and monster selection

	var zone_count: int = rng.randi_range(ZONE_COUNT_MIN, ZONE_COUNT_MAX)
	var positions: Array[Vector3] = []
	var nav_map: RID = get_world_3d().navigation_map
	var attempts: int = 0
	var max_attempts: int = zone_count * 15

	while positions.size() < zone_count and attempts < max_attempts:
		attempts += 1

		# Generate random candidate position
		var candidate := Vector3(
			rng.randf_range(-TOWN_HALF_SIZE, TOWN_HALF_SIZE),
			0.0,
			rng.randf_range(-TOWN_HALF_SIZE, TOWN_HALF_SIZE)
		)

		# Snap to NavMesh
		var nav_pos: Vector3 = NavigationServer3D.map_get_closest_point(nav_map, candidate)

		# Reject if snap was too far (zone would be off NavMesh)
		if nav_pos.distance_to(candidate) > MAX_SNAP_DISTANCE:
			continue

		# Reject if too close to player spawn (protect early game)
		if nav_pos.length() < SPAWN_EXCLUSION_RADIUS:
			continue

		# Reject if too close to any existing zone
		var too_close: bool = false
		for existing: Vector3 in positions:
			if nav_pos.distance_to(existing) < MIN_ZONE_SPACING:
				too_close = true
				break
		if too_close:
			continue

		positions.append(nav_pos)

	if positions.size() < ZONE_COUNT_MIN:
		push_warning("Ambusher: Only placed %d/%d kill zones" % [positions.size(), zone_count])

	return positions

# ---------------------------------------------------------------------------
# Warning props (subtle environmental markers)
# ---------------------------------------------------------------------------

func _place_warning_props(zone_center: Vector3) -> void:
	## Place 2-3 subtle visual warning markers near zone edges.
	## Observant players can spot these and avoid the kill zone.
	## Current implementation uses placeholder meshes -- replace with actual
	## prop models (bones, markings, disturbed ground) when art exists.
	var rng := RandomNumberGenerator.new()
	rng.seed = int(zone_center.x * 1000.0 + zone_center.z * 7.0)  # Deterministic per zone

	var nav_map: RID = get_world_3d().navigation_map
	var prop_count: int = rng.randi_range(2, 3)

	for i: int in range(prop_count):
		# Generate position within WARNING_RADIUS of zone center at random angle
		var angle: float = rng.randf_range(0.0, TAU)
		var dist: float = rng.randf_range(WARNING_RADIUS * 0.5, WARNING_RADIUS)
		var offset := Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
		var prop_pos: Vector3 = zone_center + offset

		# Snap to NavMesh
		prop_pos = NavigationServer3D.map_get_closest_point(nav_map, prop_pos)

		# Create small dark-colored marker as visual warning
		var marker := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.3, 0.1, 0.3)
		marker.mesh = box

		# Dark material for ominous appearance
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.15, 0.08, 0.08)  # Dark reddish-brown
		mat.roughness = 0.9
		marker.material_override = mat
		marker.global_position = prop_pos
		add_child(marker)

		# Faint red OmniLight3D for subtle unease -- visible in darkness but easy to miss
		var light := OmniLight3D.new()
		light.light_energy = 0.1
		light.omni_range = 2.0
		light.light_color = Color(0.6, 0.1, 0.1)  # Dark red
		light.global_position = prop_pos + Vector3(0.0, 0.3, 0.0)
		add_child(light)
