extends Node
## Manages the run objective: selects a random objective template, spawns items,
## tracks completion progress, and signals when all objectives are done.

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const OBJECTIVE_DIR: String = "res://resources/objectives/"

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var active_template: ObjectiveTemplate = null
var completed_ids: Array[String] = []
var required_count: int = 0
var objective_pool: Array[ObjectiveTemplate] = []

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_objective_pool()
	EventBus.connect("objective_completed", _on_objective_completed)
	EventBus.connect("item_picked_up", _on_item_picked_up)
	EventBus.connect("game_started", _on_game_started)


# ---------------------------------------------------------------------------
# Pool loading
# ---------------------------------------------------------------------------

func _load_objective_pool() -> void:
	var dir: DirAccess = DirAccess.open(OBJECTIVE_DIR)
	if not dir:
		push_error("ObjectiveManager: Could not open objective directory: %s" % OBJECTIVE_DIR)
		return

	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			var path: String = OBJECTIVE_DIR + file_name
			var res: Resource = load(path)
			if res is ObjectiveTemplate:
				objective_pool.append(res as ObjectiveTemplate)
		file_name = dir.get_next()
	dir.list_dir_end()


# ---------------------------------------------------------------------------
# Run setup
# ---------------------------------------------------------------------------

func setup_run(run_seed: int) -> void:
	reset()

	if objective_pool.is_empty():
		push_error("ObjectiveManager: No objective templates found in pool.")
		return

	# Use the run seed for deterministic selection
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = run_seed

	var index: int = rng.randi_range(0, objective_pool.size() - 1)
	active_template = objective_pool[index]
	required_count = active_template.required_count


func spawn_objectives(spawn_points: Array[Marker3D]) -> void:
	if active_template == null:
		push_error("ObjectiveManager: No active template — call setup_run() first.")
		return

	if active_template.item_scene == null:
		# Some objective types (SOLVE_SEQUENCE, REACH_LOCATION) don't spawn items
		return

	if spawn_points.size() < required_count:
		push_error("ObjectiveManager: Not enough spawn points (%d) for required count (%d)." \
				% [spawn_points.size(), required_count])
		return

	# Shuffle spawn points deterministically (array was passed in; we shuffle a copy)
	var shuffled: Array[Marker3D] = spawn_points.duplicate()
	shuffled.shuffle()

	for i: int in range(required_count):
		var point: Marker3D = shuffled[i]
		var instance: Node3D = active_template.item_scene.instantiate() as Node3D
		if instance == null:
			push_error("ObjectiveManager: Failed to instantiate item scene.")
			continue

		point.add_child(instance)
		instance.global_position = point.global_position


# ---------------------------------------------------------------------------
# Progress tracking
# ---------------------------------------------------------------------------

func _on_objective_completed(objective_id: String) -> void:
	if completed_ids.has(objective_id):
		return
	completed_ids.append(objective_id)
	_check_completion()


func _on_item_picked_up(item_id: String) -> void:
	# Items that match the active template's objective type count toward completion
	if active_template == null:
		return
	if active_template.type != ObjectiveTemplate.ObjectiveType.FIND_ITEMS:
		return
	if completed_ids.has(item_id):
		return
	completed_ids.append(item_id)
	_check_completion()


func _check_completion() -> void:
	if completed_ids.size() >= required_count:
		EventBus.emit_signal("all_objectives_completed")


func get_progress() -> Dictionary:
	return {
		"completed": completed_ids.size(),
		"required": required_count,
	}


# ---------------------------------------------------------------------------
# Reset
# ---------------------------------------------------------------------------

func reset() -> void:
	active_template = null
	completed_ids.clear()
	required_count = 0


# ---------------------------------------------------------------------------
# Signal callbacks
# ---------------------------------------------------------------------------

func _on_game_started(run_seed: int) -> void:
	setup_run(run_seed)
