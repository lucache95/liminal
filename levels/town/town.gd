extends Node3D
## Main town level controller.
## Handles player/monster spawning, objectives, audio zones, and day/night.

enum MonsterType { STALKER, LURKER, AMBUSHER }

const MONSTER_SCENES: Dictionary = {
	MonsterType.STALKER: "res://enemies/stalker/stalker.tscn",
	MonsterType.LURKER: "res://enemies/lurker/lurker.tscn",
	MonsterType.AMBUSHER: "res://enemies/ambusher/ambusher.tscn",
}

@onready var player_spawn: Marker3D = $PlayerSpawn
@onready var patrol_points: Node3D = $PatrolPoints
@onready var moonlight: DirectionalLight3D = $DirectionalLight3D
@onready var audio_zones: Node3D = $AudioZones

var _current_ambient_zone: StringName = &"default"


func _ready() -> void:
	# All buildings and props are static scene instances in town.tscn
	_spawn_player()
	_spawn_monster()
	_create_retreat_points()
	_setup_objectives()
	_connect_audio_zones()
	_setup_ui()
	_setup_atmosphere()

	if OS.is_debug_build():
		# Defer to next frame so navmesh is ready
		call_deferred("_validate_navmesh")
		# Log performance metrics every 5 seconds
		var perf_timer: Timer = Timer.new()
		perf_timer.wait_time = 5.0
		perf_timer.timeout.connect(PerformanceValidator.log_metrics)
		add_child(perf_timer)
		perf_timer.start()


func _validate_navmesh() -> void:
	NavMeshValidator.validate(self)


func _setup_ui() -> void:
	add_child(preload("res://ui/hud/hud.tscn").instantiate())
	add_child(preload("res://ui/pause_menu/pause_menu.tscn").instantiate())
	add_child(preload("res://ui/death_screen/death_screen.tscn").instantiate())
	add_child(preload("res://shaders/post_process.tscn").instantiate())


func _setup_atmosphere() -> void:
	var world_env: WorldEnvironment = $WorldEnvironment

	# Day/night cycle system
	var day_night: DayNightCycle = DayNightCycle.new()
	day_night.name = "DayNightCycle"
	day_night.world_env = world_env
	day_night.sun_light = moonlight
	day_night.run_duration = GameManager.max_run_time
	add_child(day_night)

	# Weather preset system
	var weather: WeatherManager = WeatherManager.new()
	weather.name = "WeatherManager"
	add_child(weather)
	weather.apply_weather(GameManager.current_seed, world_env.environment)


func _spawn_player() -> void:
	var player_scene: PackedScene = preload("res://player/player.tscn")
	var player: CharacterBody3D = player_scene.instantiate()
	player.global_position = player_spawn.global_position
	add_child(player)
	EventBus.emit_signal("player_spawned", player)


func _spawn_monster() -> void:
	# Select monster type deterministically from run seed
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = GameManager.current_seed ^ 0x4D4F4E53  # XOR hash to decorrelate from weather
	var selected_type: int = rng.randi_range(0, 2)

	EventBus.monster_type_selected.emit(MonsterType.keys()[selected_type])

	# Resolve scene path with fallback to Stalker
	var scene_path: String = MONSTER_SCENES[selected_type]
	if not ResourceLoader.exists(scene_path):
		push_warning("Town: Monster type %s scene not found, falling back to Stalker" % MonsterType.keys()[selected_type])
		selected_type = MonsterType.STALKER
		scene_path = MONSTER_SCENES[MonsterType.STALKER]

	var monster_scene: PackedScene = load(scene_path)
	var monster: Node3D = monster_scene.instantiate() as Node3D

	# Ambusher is a static trap system -- no spawn point needed, handles own setup
	if selected_type == MonsterType.AMBUSHER:
		add_child(monster)
		return

	# Pick a random monster spawn point (Stalker/Lurker)
	var spawns: Array[Marker3D] = []
	for child: Node in $MonsterSpawns.get_children():
		if child is Marker3D:
			spawns.append(child)

	if spawns.is_empty():
		push_error("Town: No monster spawn points found")
		monster.queue_free()
		return

	var chosen_spawn: Marker3D = spawns.pick_random()
	monster.global_position = chosen_spawn.global_position
	add_child(monster)

	# Instantiate AI Director for Stalker runs only
	if selected_type == MonsterType.STALKER:
		var director: AIDirector = AIDirector.new()
		director.name = "AIDirector"
		add_child(director)


func _create_retreat_points() -> void:
	## Create Marker3D nodes at map extremes for AI Director retreat navigation.
	var positions: Array[Vector3] = [
		Vector3(-80.0, 0.0, -80.0),   # NW
		Vector3(80.0, 0.0, -80.0),    # NE
		Vector3(80.0, 0.0, 80.0),     # SE
		Vector3(-80.0, 0.0, 80.0),    # SW
		Vector3(0.0, 0.0, -85.0),     # N
		Vector3(0.0, 0.0, 85.0),      # S
	]

	for i: int in range(positions.size()):
		var marker: Marker3D = Marker3D.new()
		marker.name = "RetreatPoint%d" % i
		marker.position = positions[i]
		marker.add_to_group(&"retreat_point")
		add_child(marker)


func _setup_objectives() -> void:
	var spawn_points: Array[Marker3D] = []
	for child: Node in $ObjectiveSpawns.get_children():
		if child is Marker3D:
			spawn_points.append(child)
	if spawn_points.size() > 0:
		ObjectiveManager.spawn_objectives(spawn_points)

	# Place environmental clues near active objective spawn locations
	if ObjectiveManager.active_template != null and ObjectiveManager._run_rng != null:
		var clue_mgr: EnvironmentalClueManager = EnvironmentalClueManager.new()
		clue_mgr.name = "EnvironmentalClueManager"
		add_child(clue_mgr)

		# Collect the actual spawn positions used (first N of shuffled points)
		# Since spawn_objectives already shuffled and used first required_count,
		# we need the positions of the spawned items.
		# The items were added as children of the Marker3D points.
		var used_positions: Array[Vector3] = []
		for i: int in range(spawn_points.size()):
			var point: Marker3D = spawn_points[i]
			# If this point has children beyond its original state, it was used for spawning
			if point.get_child_count() > 0:
				used_positions.append(point.global_position)

		if not used_positions.is_empty():
			# Create a clue-specific RNG seeded from run seed for deterministic clue placement
			var clue_rng: RandomNumberGenerator = RandomNumberGenerator.new()
			clue_rng.seed = GameManager.current_seed ^ 0x434C5545  # "CLUE" XOR hash
			clue_mgr.place_clues(ObjectiveManager.active_template, used_positions, clue_rng)


func _connect_audio_zones() -> void:
	var town_center_zone: Area3D = audio_zones.get_node("TownCenterZone")
	var industrial_zone: Area3D = audio_zones.get_node("IndustrialZone")
	var forest_edge_zone: Area3D = audio_zones.get_node("ForestEdgeZone")
	var highway_zone: Area3D = audio_zones.get_node("HighwayZone")

	town_center_zone.body_entered.connect(_on_zone_entered.bind(&"town_center"))
	town_center_zone.body_exited.connect(_on_zone_exited.bind(&"town_center"))

	industrial_zone.body_entered.connect(_on_zone_entered.bind(&"industrial"))
	industrial_zone.body_exited.connect(_on_zone_exited.bind(&"industrial"))

	forest_edge_zone.body_entered.connect(_on_zone_entered.bind(&"forest_edge"))
	forest_edge_zone.body_exited.connect(_on_zone_exited.bind(&"forest_edge"))

	highway_zone.body_entered.connect(_on_zone_entered.bind(&"highway"))
	highway_zone.body_exited.connect(_on_zone_exited.bind(&"highway"))


func _on_zone_entered(body: Node3D, zone_name: StringName) -> void:
	if not body.is_in_group(&"player"):
		return
	_current_ambient_zone = zone_name
	# AudioManager.set_ambient_zone(zone_name) -- called when available


func _on_zone_exited(body: Node3D, zone_name: StringName) -> void:
	if not body.is_in_group(&"player"):
		return
	if _current_ambient_zone == zone_name:
		_current_ambient_zone = &"default"
		# AudioManager.set_ambient_zone(&"default") -- called when available


