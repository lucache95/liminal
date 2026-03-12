class_name ModelReplacer
extends Node
## Spawns runtime props around the town.
## Buildings are now static scene instances in town.tscn (not runtime-loaded).

## Additional props scattered around the town.
const PROP_SPAWNS: Array[Dictionary] = [
	{"scene": "res://assets/models/props/wooden_barrel.glb", "pos": Vector3(-28, 0, -22), "rot_y": 0.0},
	{"scene": "res://assets/models/props/wooden_barrel.glb", "pos": Vector3(-32, 0, -27), "rot_y": 45.0},
	{"scene": "res://assets/models/props/dumpster.glb", "pos": Vector3(15, 0, 18), "rot_y": 90.0},
	{"scene": "res://assets/models/props/dumpster.glb", "pos": Vector3(-38, 0, 5), "rot_y": 0.0},
	{"scene": "res://assets/models/props/old_car.glb", "pos": Vector3(25, 0, -28), "rot_y": -30.0},
	{"scene": "res://assets/models/props/old_car.glb", "pos": Vector3(-25, 0, -30), "rot_y": 160.0},
	{"scene": "res://assets/models/props/rusty_gate.glb", "pos": Vector3(30, 0, 10), "rot_y": 0.0},
	{"scene": "res://assets/models/props/wooden_crate.glb", "pos": Vector3(-33, 0, 15), "rot_y": 15.0},
	{"scene": "res://assets/models/props/wooden_crate.glb", "pos": Vector3(-30, 0, 17), "rot_y": -10.0},
	{"scene": "res://assets/models/props/generator.glb", "pos": Vector3(-35, 0, 0), "rot_y": 0.0},
	{"scene": "res://assets/models/props/street_lamp.glb", "pos": Vector3(8, 0, 8), "rot_y": 0.0},
	{"scene": "res://assets/models/props/street_lamp.glb", "pos": Vector3(-8, 0, -8), "rot_y": 0.0},
	{"scene": "res://assets/models/props/street_lamp.glb", "pos": Vector3(0, 0, 20), "rot_y": 0.0},
	{"scene": "res://assets/models/props/street_lamp.glb", "pos": Vector3(-30, 0, -18), "rot_y": 0.0},
]


static func spawn_props(town_root: Node3D) -> void:
	_spawn_props(town_root)


static func _spawn_props(town_root: Node3D) -> void:
	var props_container := Node3D.new()
	props_container.name = "ScatteredProps"
	town_root.add_child(props_container)

	for prop_data: Dictionary in PROP_SPAWNS:
		var scene_path: String = prop_data["scene"]
		if not ResourceLoader.exists(scene_path):
			continue

		var glb_scene: PackedScene = load(scene_path) as PackedScene
		if glb_scene == null:
			continue

		var instance: Node3D = glb_scene.instantiate()
		instance.position = prop_data["pos"]
		instance.rotation_degrees.y = prop_data["rot_y"]
		props_container.add_child(instance)
