class_name ModelReplacer
extends Node
## Replaces placeholder BoxMesh nodes with imported GLB models at runtime.
## Attach to the Town scene and call replace_all() from _ready().

## Maps node paths (relative to town root) to GLB scene paths.
const REPLACEMENTS: Dictionary = {
	# Main Street shops → general_store
	"MainStreet/Shop01/Mesh": "res://assets/models/environment/general_store.glb",
	"MainStreet/Shop02/Mesh": "res://assets/models/environment/abandoned_house_01.glb",
	"MainStreet/Shop03/Mesh": "res://assets/models/environment/general_store.glb",
	"MainStreet/Shop04/Mesh": "res://assets/models/environment/abandoned_house_02.glb",
	# Gas station
	"GasStation/MainBuilding/Mesh": "res://assets/models/environment/gas_station.glb",
	# Church
	"Church/ChurchBuilding/Mesh": "res://assets/models/environment/church.glb",
	# Industrial warehouses
	"IndustrialArea/Warehouse01/Mesh": "res://assets/models/environment/warehouse.glb",
	"IndustrialArea/Warehouse02/Mesh": "res://assets/models/environment/warehouse.glb",
	# Residential houses
	"ResidentialArea/House01/Mesh": "res://assets/models/environment/abandoned_house_01.glb",
	"ResidentialArea/House02/Mesh": "res://assets/models/environment/abandoned_house_02.glb",
	"ResidentialArea/House03/Mesh": "res://assets/models/environment/abandoned_house_01.glb",
	# Town square benches
	"TownSquare/Bench01/Mesh": "res://assets/models/props/park_bench.glb",
	"TownSquare/Bench02/Mesh": "res://assets/models/props/park_bench.glb",
	"TownSquare/Bench03/Mesh": "res://assets/models/props/park_bench.glb",
	"TownSquare/Bench04/Mesh": "res://assets/models/props/park_bench.glb",
}

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


static func replace_all(town_root: Node3D) -> void:
	_replace_meshes(town_root)
	_spawn_props(town_root)


static func _replace_meshes(town_root: Node3D) -> void:
	for node_path: String in REPLACEMENTS:
		var glb_path: String = REPLACEMENTS[node_path]
		if not ResourceLoader.exists(glb_path):
			continue

		var mesh_node: Node = town_root.get_node_or_null(node_path)
		if mesh_node == null:
			continue

		var glb_scene: PackedScene = load(glb_path) as PackedScene
		if glb_scene == null:
			continue

		var model_instance: Node3D = glb_scene.instantiate()
		var parent: Node = mesh_node.get_parent()

		# Hide the placeholder mesh instead of removing (keeps collision working)
		(mesh_node as Node3D).visible = false

		# Add GLB model as sibling, centered at parent's origin
		model_instance.name = "Model"
		parent.add_child(model_instance)


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
