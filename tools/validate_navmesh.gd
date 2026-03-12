@tool
class_name NavMeshValidator
extends Node

## Validates monster can pathfind between all spawn points and objectives.
## Attach to any node in the scene tree and call validate() from the editor
## or add to town.gd _ready() for debug builds.


static func validate(town: Node3D) -> bool:
	var nav_map: RID = NavigationServer3D.get_maps()[0]
	var all_passed := true
	var spawn_points: Array[Node3D] = []
	var objective_points: Array[Node3D] = []

	var monster_spawns := town.get_node_or_null("MonsterSpawns")
	if monster_spawns:
		for child in monster_spawns.get_children():
			spawn_points.append(child)

	var objective_spawns := town.get_node_or_null("ObjectiveSpawns")
	if objective_spawns:
		for child in objective_spawns.get_children():
			objective_points.append(child)

	if spawn_points.is_empty() or objective_points.is_empty():
		push_warning("NavMeshValidator: No spawn or objective points found")
		return false

	for spawn in spawn_points:
		for obj in objective_points:
			var path: PackedVector3Array = NavigationServer3D.map_get_path(
				nav_map, spawn.global_position, obj.global_position, true
			)
			if path.is_empty():
				push_error("NavMeshValidator FAIL: No path from %s to %s" % [spawn.name, obj.name])
				all_passed = false
			else:
				print("NavMeshValidator OK: %s -> %s (%d waypoints)" % [spawn.name, obj.name, path.size()])

	if all_passed:
		print("NavMeshValidator: ALL PATHS VALID (%d spawns x %d objectives)" % [spawn_points.size(), objective_points.size()])
	else:
		push_error("NavMeshValidator: SOME PATHS FAILED - check navmesh bake")

	return all_passed
