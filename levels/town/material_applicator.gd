extends Node
## Auto-applies materials to imported GLB models that lack embedded textures.

const MATERIAL_MAP: Dictionary = {
	"concrete": "res://materials/concrete_wall.tres",
	"wood": "res://materials/old_wood.tres",
	"metal": "res://materials/rusty_metal.tres",
	"brick": "res://materials/brick.tres",
	"dark": "res://materials/dark_creature.tres",
}

# Map scene file path keywords to material types
const PATH_MATERIALS: Dictionary = {
	"general_store": "concrete", "diner": "concrete", "hardware_store": "concrete",
	"bar_tavern": "wood", "gas_station": "concrete", "church": "brick",
	"warehouse": "metal", "factory": "metal", "abandoned_house": "wood",
	"house_colonial": "wood", "house_ranch": "wood", "motel": "concrete",
	"radio_station": "metal", "school": "brick", "ranger_station": "wood",
	"pharmacy": "concrete", "trailer_home": "metal",
	"street_lamp": "metal", "park_bench": "wood", "mailbox": "metal",
	"fire_hydrant": "metal", "phone_booth": "metal", "trash_can": "metal",
	"rusty_gate": "metal", "chain_link_fence": "metal", "road_barrier": "metal",
	"traffic_cone": "metal", "old_car": "metal", "pickup_truck": "metal",
	"police_car": "metal", "wooden_barrel": "wood", "dumpster": "metal",
	"wooden_crate": "wood", "generator": "metal", "tire_stack": "metal",
	"dead_tree": "wood", "overgrown_bushes": "wood", "overturned_table": "wood",
	"broken_chair": "wood", "old_tv": "metal", "torn_couch": "wood",
	"rusted_refrigerator": "metal", "fallen_bookshelf": "wood",
	"filing_cabinet": "metal",
	"echo_walker": "dark", "lantern_widow": "dark", "window_man": "dark",
}

var _material_cache: Dictionary = {}
var _applied_count: int = 0


func _ready() -> void:
	for mat_type: String in MATERIAL_MAP:
		var path: String = MATERIAL_MAP[mat_type]
		if ResourceLoader.exists(path):
			_material_cache[mat_type] = load(path)
	call_deferred("_apply_all")


func _apply_all() -> void:
	_apply_recursive(get_parent())
	print("MaterialApplicator: applied materials to %d meshes" % _applied_count)


func _apply_recursive(node: Node) -> void:
	if node is MeshInstance3D:
		var mi: MeshInstance3D = node as MeshInstance3D
		if mi.material_override == null and mi.mesh:
			var needs_mat := false
			for s: int in mi.mesh.get_surface_count():
				if mi.mesh.surface_get_material(s) == null:
					needs_mat = true
					break
			if needs_mat:
				var mat_type: String = _resolve_material(node)
				if mat_type in _material_cache:
					mi.material_override = _material_cache[mat_type]
					_applied_count += 1

	for child: Node in node.get_children():
		_apply_recursive(child)


func _resolve_material(node: Node) -> String:
	var current: Node = node
	while current and current != get_parent():
		# Check scene_file_path (set on GLB instance roots)
		if current.scene_file_path != "":
			var path_lower: String = current.scene_file_path.to_lower()
			for key: String in PATH_MATERIALS:
				if key in path_lower:
					return PATH_MATERIALS[key]
		# Check node name
		var name_lower: String = current.name.to_lower()
		for key: String in PATH_MATERIALS:
			if key in name_lower:
				return PATH_MATERIALS[key]
		current = current.get_parent()
	return "concrete"
