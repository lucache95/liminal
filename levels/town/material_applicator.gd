extends Node
## Auto-applies materials to imported GLB models that lack embedded textures.
## Attach to Town scene root or add as autoload.

const MATERIAL_MAP: Dictionary = {
	"concrete": "res://materials/concrete_wall.tres",
	"wood": "res://materials/old_wood.tres",
	"metal": "res://materials/rusty_metal.tres",
	"asphalt": "res://materials/asphalt.tres",
	"grass": "res://materials/grass.tres",
}

# Map building/prop names to material types
const NODE_MATERIALS: Dictionary = {
	# Buildings
	"general_store": "concrete",
	"diner": "concrete",
	"hardware_store": "concrete",
	"bar_tavern": "wood",
	"gas_station": "concrete",
	"church": "concrete",
	"warehouse": "metal",
	"factory": "metal",
	"abandoned_house": "wood",
	"house_colonial": "wood",
	"house_ranch": "wood",
	"motel": "concrete",
	"radio_station": "metal",
	"school": "concrete",
	"ranger_station": "wood",
	"pharmacy": "concrete",
	"trailer_home": "metal",
	# Props
	"street_lamp": "metal",
	"park_bench": "wood",
	"mailbox": "metal",
	"fire_hydrant": "metal",
	"phone_booth": "metal",
	"trash_can": "metal",
	"rusty_gate": "metal",
	"chain_link_fence": "metal",
	"road_barrier": "metal",
	"traffic_cone": "metal",
	"old_car": "metal",
	"pickup_truck": "metal",
	"police_car": "metal",
	"wooden_barrel": "wood",
	"dumpster": "metal",
	"wooden_crate": "wood",
	"generator": "metal",
	"tire_stack": "metal",
	"dead_tree": "wood",
	"overgrown_bushes": "wood",
	"overturned_table": "wood",
	"broken_chair": "wood",
	"old_tv": "metal",
	"torn_couch": "wood",
	"rusted_refrigerator": "metal",
	"fallen_bookshelf": "wood",
	"filing_cabinet": "metal",
}

var _material_cache: Dictionary = {}


func _ready() -> void:
	# Pre-load materials
	for mat_type: String in MATERIAL_MAP:
		var path: String = MATERIAL_MAP[mat_type]
		if ResourceLoader.exists(path):
			_material_cache[mat_type] = load(path)

	# Apply materials to all GLB instances in the scene tree
	call_deferred("_apply_materials_recursive", get_parent())


func _apply_materials_recursive(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_inst: MeshInstance3D = node as MeshInstance3D
		# Skip if already has a material
		if mesh_inst.material_override != null:
			return
		if mesh_inst.mesh and mesh_inst.mesh.get_surface_count() > 0:
			var has_material := false
			for s: int in mesh_inst.mesh.get_surface_count():
				if mesh_inst.mesh.surface_get_material(s) != null:
					has_material = true
					break
			if not has_material:
				# Find material type from ancestor node names
				var mat_type: String = _find_material_for_node(node)
				if mat_type in _material_cache:
					mesh_inst.material_override = _material_cache[mat_type]

	for child: Node in node.get_children():
		_apply_materials_recursive(child)


func _find_material_for_node(node: Node) -> String:
	"""Walk up the tree to find matching material from NODE_MATERIALS."""
	var current: Node = node
	while current != null:
		var node_name_lower: String = current.name.to_lower()
		for key: String in NODE_MATERIALS:
			if key in node_name_lower:
				return NODE_MATERIALS[key]
		# Also check the scene file path for instanced scenes
		if current.scene_file_path != "":
			var scene_lower: String = current.scene_file_path.to_lower()
			for key: String in NODE_MATERIALS:
				if key in scene_lower:
					return NODE_MATERIALS[key]
		current = current.get_parent()
	return "concrete"  # fallback
