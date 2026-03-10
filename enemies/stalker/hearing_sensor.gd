extends Node3D
## Handles sound-based detection for the monster.
## Listens to EventBus.sound_emitted, filters by range and occlusion.

const SOUND_MEMORY_DURATION: float = 5.0
const OCCLUSION_INTENSITY_MULTIPLIER: float = 0.5
const MIN_PERCEIVED_INTENSITY: float = 0.1

var _sound_queue: Array[Dictionary] = []
var _config: MonsterConfig


func _ready() -> void:
	EventBus.sound_emitted.connect(_on_sound_emitted)


## Must be called by the stalker after it sets up the config reference.
func initialize(config: MonsterConfig) -> void:
	_config = config


func _process(delta: float) -> void:
	_cleanup_old_sounds(delta)


## Returns the most recent sound event that passed the detection threshold.
## Returns an empty Dictionary if no relevant sounds exist.
func get_latest_sound() -> Dictionary:
	if _sound_queue.is_empty():
		return {}
	# Return the most recent sound (last in queue, sorted by time added)
	return _sound_queue.back()


## Returns all currently stored sound events.
func get_all_sounds() -> Array[Dictionary]:
	return _sound_queue


## Clears the sound queue (e.g., when transitioning to a new state).
func clear_sounds() -> void:
	_sound_queue.clear()


func _on_sound_emitted(position: Vector3, intensity: float, source: String) -> void:
	if _config == null:
		return

	var monster_pos: Vector3 = global_position
	var distance: float = monster_pos.distance_to(position)

	# Filter by hearing range
	if distance > _config.hearing_range:
		return

	# Attenuate intensity by distance (inverse linear falloff)
	var distance_factor: float = 1.0 - clampf(distance / _config.hearing_range, 0.0, 1.0)
	var perceived_intensity: float = intensity * distance_factor

	# Check occlusion — if something blocks line to the sound, reduce intensity
	if not _has_line_to_sound(monster_pos, position):
		perceived_intensity *= OCCLUSION_INTENSITY_MULTIPLIER

	# Only store if perceived intensity is above the minimum threshold
	if perceived_intensity < MIN_PERCEIVED_INTENSITY:
		return

	var sound_event: Dictionary = {
		"position": position,
		"intensity": perceived_intensity,
		"original_intensity": intensity,
		"source": source,
		"age": 0.0,
	}
	_sound_queue.append(sound_event)


## Performs a physics raycast to check if the path to a sound source is occluded.
func _has_line_to_sound(from_pos: Vector3, sound_pos: Vector3) -> bool:
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	if space_state == null:
		return true # Assume unoccluded if we cannot query

	var eye_offset: Vector3 = Vector3.UP * 1.6
	var from: Vector3 = from_pos + eye_offset
	var to: Vector3 = sound_pos

	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1 # World geometry only
	query.collide_with_areas = false

	var result: Dictionary = space_state.intersect_ray(query)
	return result.is_empty()


## Ages all sounds and removes those older than SOUND_MEMORY_DURATION.
func _cleanup_old_sounds(delta: float) -> void:
	var i: int = _sound_queue.size() - 1
	while i >= 0:
		_sound_queue[i]["age"] += delta
		if _sound_queue[i]["age"] > SOUND_MEMORY_DURATION:
			_sound_queue.remove_at(i)
		i -= 1
