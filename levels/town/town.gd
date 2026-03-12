extends Node3D
## Main town level controller.
## Handles player/monster spawning, objectives, audio zones, and day/night.

@onready var player_spawn: Marker3D = $PlayerSpawn
@onready var patrol_points: Node3D = $PatrolPoints
@onready var moonlight: DirectionalLight3D = $DirectionalLight3D
@onready var audio_zones: Node3D = $AudioZones

var _current_ambient_zone: StringName = &"default"


func _ready() -> void:
	# All buildings and props are static scene instances in town.tscn
	_spawn_player()
	_spawn_monster()
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
	var monster_scene: PackedScene = preload("res://enemies/stalker/stalker.tscn")
	var monster: CharacterBody3D = monster_scene.instantiate()

	# Pick a random monster spawn point
	var spawns: Array[Marker3D] = []
	for child: Node in $MonsterSpawns.get_children():
		if child is Marker3D:
			spawns.append(child)

	if spawns.is_empty():
		push_error("Town: No monster spawn points found")
		return

	var chosen_spawn: Marker3D = spawns.pick_random()
	monster.global_position = chosen_spawn.global_position
	add_child(monster)


func _setup_objectives() -> void:
	var spawn_points: Array[Marker3D] = []
	for child: Node in $ObjectiveSpawns.get_children():
		if child is Marker3D:
			spawn_points.append(child)
	if spawn_points.size() > 0:
		ObjectiveManager.spawn_objectives(spawn_points)


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


