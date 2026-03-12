extends Node3D
## Small test level for validating player controller, lighting, and atmosphere.

@onready var player_spawn: Marker3D = $PlayerSpawn
@onready var patrol_points: Node3D = $PatrolPoints


func _ready() -> void:
	_spawn_player()
	_spawn_monster()
	_setup_objectives()
	_setup_ui()


func _spawn_player() -> void:
	var player_scene: PackedScene = preload("res://player/player.tscn")
	var player: CharacterBody3D = player_scene.instantiate()
	player.global_position = player_spawn.global_position
	add_child(player)
	EventBus.emit_signal("player_spawned", player)


func _spawn_monster() -> void:
	var monster_scene: PackedScene = preload("res://enemies/stalker/stalker.tscn")
	var monster: CharacterBody3D = monster_scene.instantiate()
	monster.global_position = $MonsterSpawn.global_position
	add_child(monster)


func _setup_objectives() -> void:
	var spawn_points: Array[Marker3D] = []
	for child: Node in $ObjectiveSpawns.get_children():
		if child is Marker3D:
			spawn_points.append(child)
	if spawn_points.size() > 0:
		ObjectiveManager.spawn_objectives(spawn_points)


func _setup_ui() -> void:
	var hud: PackedScene = preload("res://ui/hud/hud.tscn")
	add_child(hud.instantiate())

	var pause_menu: PackedScene = preload("res://ui/pause_menu/pause_menu.tscn")
	add_child(pause_menu.instantiate())

	var death_screen: PackedScene = preload("res://ui/death_screen/death_screen.tscn")
	add_child(death_screen.instantiate())

	var post_process: PackedScene = preload("res://shaders/post_process.tscn")
	add_child(post_process.instantiate())
