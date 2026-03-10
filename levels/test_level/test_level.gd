extends Node3D
## Small test level for validating player controller, lighting, and atmosphere.

@onready var player_spawn: Marker3D = $PlayerSpawn
@onready var patrol_points: Node3D = $PatrolPoints


func _ready() -> void:
	_spawn_player()
	_spawn_monster()
	_setup_objectives()


func _spawn_player() -> void:
	var player_scene: PackedScene = preload("res://player/player.tscn")
	var player: CharacterBody3D = player_scene.instantiate()
	player.global_position = player_spawn.global_position
	add_child(player)
	EventBus.player_spawned.emit(player)


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
	# ObjectiveManager.spawn_objectives(spawn_points) -- called when available
