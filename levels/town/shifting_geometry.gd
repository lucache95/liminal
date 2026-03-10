class_name ShiftingGeometry
extends Node3D
## Attach to buildings/objects that can shift position when not observed by the player.
## Checks camera frustum visibility and line-of-sight occlusion before shifting.

## Possible alternate positions this node can shift to (local space).
@export var alternate_positions: Array[Vector3] = []
## Seconds the node must be unobserved before a shift can occur.
@export var shift_delay: float = 5.0
## Probability (0.0 - 1.0) that a shift happens once the delay has elapsed.
@export var shift_chance: float = 0.3
## If true, can also randomly rotate by 90-degree increments when shifting.
@export var can_rotate: bool = false
## If true, can swap visibility of child nodes instead of moving.
@export var can_swap_children: bool = false

var _unobserved_timer: float = 0.0
var _original_position: Vector3
var _current_position_index: int = -1  # -1 = original position
var _camera: Camera3D = null


func _ready() -> void:
	_original_position = position


func _process(delta: float) -> void:
	if _camera == null:
		_camera = get_viewport().get_camera_3d()
		if _camera == null:
			return

	if _is_observed():
		_unobserved_timer = 0.0
	else:
		_unobserved_timer += delta
		if _unobserved_timer >= shift_delay:
			_try_shift()
			_unobserved_timer = 0.0


func _is_observed() -> bool:
	if _camera == null:
		return true  # Assume observed if no camera

	# Check if within camera frustum
	if not _is_in_frustum():
		return false

	# Check line of sight via raycast
	if not _has_line_of_sight():
		return false

	return true


func _is_in_frustum() -> bool:
	var frustum_planes: Array[Plane] = _camera.get_frustum()
	var check_position: Vector3 = global_position

	# Get an approximate bounding radius from child meshes
	var radius: float = _get_approximate_radius()

	for plane: Plane in frustum_planes:
		if plane.distance_to(check_position) < -radius:
			return false

	return true


func _has_line_of_sight() -> bool:
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var from: Vector3 = _camera.global_position
	var to: Vector3 = global_position

	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1  # World geometry only
	query.exclude = _get_own_rids()

	var result: Dictionary = space_state.intersect_ray(query)

	# If ray hit something between camera and us, we are occluded
	if result.is_empty():
		return true  # Nothing blocking, we are visible

	var hit_distance: float = from.distance_to(result["position"])
	var self_distance: float = from.distance_to(global_position)

	return hit_distance >= self_distance * 0.9


func _get_own_rids() -> Array[RID]:
	var rids: Array[RID] = []
	for child: Node in get_children():
		if child is CollisionObject3D:
			rids.append(child.get_rid())
	if self is CollisionObject3D:
		rids.append((self as CollisionObject3D).get_rid())
	return rids


func _get_approximate_radius() -> float:
	var max_extent: float = 1.0
	for child: Node in get_children():
		if child is MeshInstance3D:
			var mesh_instance: MeshInstance3D = child as MeshInstance3D
			var aabb: AABB = mesh_instance.get_aabb()
			var extent: float = aabb.size.length() * 0.5
			if extent > max_extent:
				max_extent = extent
	return max_extent


func _try_shift() -> void:
	if randf() > shift_chance:
		return

	if can_swap_children:
		_swap_child_visibility()
	elif alternate_positions.size() > 0:
		_shift_position()

	if can_rotate:
		_shift_rotation()

	EventBus.geometry_shifted.emit(get_path())


func _shift_position() -> void:
	if alternate_positions.is_empty():
		return

	# Build list of available positions (include original)
	var positions: Array[Vector3] = [_original_position]
	positions.append_array(alternate_positions)

	# Pick a different position than current
	var current_pos: Vector3 = position
	var candidates: Array[Vector3] = []
	for pos: Vector3 in positions:
		if not pos.is_equal_approx(current_pos):
			candidates.append(pos)

	if candidates.is_empty():
		return

	position = candidates.pick_random()


func _shift_rotation() -> void:
	var rotation_options: Array[float] = [0.0, 90.0, 180.0, 270.0]
	var current_y: float = snapped(rotation_degrees.y, 90.0)
	var candidates: Array[float] = []
	for rot: float in rotation_options:
		if not is_equal_approx(rot, current_y):
			candidates.append(rot)

	if candidates.is_empty():
		return

	rotation_degrees.y = candidates.pick_random()


func _swap_child_visibility() -> void:
	var visible_children: Array[Node3D] = []
	var hidden_children: Array[Node3D] = []

	for child: Node in get_children():
		if child is Node3D:
			var child_3d: Node3D = child as Node3D
			if child_3d.visible:
				visible_children.append(child_3d)
			else:
				hidden_children.append(child_3d)

	# Swap: hide one visible, show one hidden
	if visible_children.size() > 0 and hidden_children.size() > 0:
		var to_hide: Node3D = visible_children.pick_random()
		var to_show: Node3D = hidden_children.pick_random()
		to_hide.visible = false
		to_show.visible = true
