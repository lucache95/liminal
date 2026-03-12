class_name FootstepSystem
extends RayCast3D
## Detects floor surface material and plays appropriate footstep sounds.

enum Surface {
	CONCRETE,
	WOOD,
	METAL,
	DIRT,
	GRASS,
	WATER,
}

# Preloaded sound pools per surface type (placeholder paths).
# Each surface has an array of AudioStream references. Files may not exist yet.
var _footstep_sounds: Dictionary = {}

# Concrete
var _concrete_paths: Array[String] = [
	"res://assets/audio/sfx/footstep_concrete_01.wav",
	"res://assets/audio/sfx/footstep_concrete_02.wav",
	"res://assets/audio/sfx/footstep_concrete_03.wav",
]

# Wood
var _wood_paths: Array[String] = [
	"res://assets/audio/sfx/footstep_wood_01.wav",
	"res://assets/audio/sfx/footstep_wood_02.wav",
	"res://assets/audio/sfx/footstep_wood_03.wav",
]

# Metal
var _metal_paths: Array[String] = [
	"res://assets/audio/sfx/footstep_metal_01.wav",
	"res://assets/audio/sfx/footstep_metal_02.wav",
	"res://assets/audio/sfx/footstep_metal_03.wav",
]

# Dirt
var _dirt_paths: Array[String] = [
	"res://assets/audio/sfx/footstep_dirt_01.wav",
	"res://assets/audio/sfx/footstep_dirt_02.wav",
	"res://assets/audio/sfx/footstep_dirt_03.wav",
]

# Grass
var _grass_paths: Array[String] = [
	"res://assets/audio/sfx/footstep_grass_01.wav",
	"res://assets/audio/sfx/footstep_grass_02.wav",
	"res://assets/audio/sfx/footstep_grass_03.wav",
]

# Water — actual files are mp3 in footsteps/ directory
var _water_paths: Array[String] = [
	"res://assets/audio/footsteps/water_step_1.mp3",
	"res://assets/audio/footsteps/water_step_2.mp3",
	"res://assets/audio/footsteps/water_step_3.mp3",
]

@onready var _audio_player: AudioStreamPlayer3D = get_parent().get_node("FootstepAudio") as AudioStreamPlayer3D


func _ready() -> void:
	enabled = true
	_load_sounds()


## Determine the current floor surface from the collider's metadata or physics material.
func get_current_surface() -> Surface:
	if not is_colliding():
		return Surface.CONCRETE  # Default fallback

	var collider: Object = get_collider()
	if collider == null:
		return Surface.CONCRETE

	# Check for "surface" metadata on the collider node
	if collider is Node and (collider as Node).has_meta("surface"):
		var surface_name: String = str((collider as Node).get_meta("surface")).to_upper()
		match surface_name:
			"CONCRETE":
				return Surface.CONCRETE
			"WOOD":
				return Surface.WOOD
			"METAL":
				return Surface.METAL
			"DIRT":
				return Surface.DIRT
			"GRASS":
				return Surface.GRASS
			"WATER":
				return Surface.WATER

	# Check for physics material on a StaticBody3D
	if collider is StaticBody3D:
		var static_body: StaticBody3D = collider as StaticBody3D
		if static_body.physics_material_override:
			var mat_name: String = static_body.physics_material_override.resource_name.to_upper()
			if mat_name.contains("WOOD"):
				return Surface.WOOD
			elif mat_name.contains("METAL"):
				return Surface.METAL
			elif mat_name.contains("DIRT"):
				return Surface.DIRT
			elif mat_name.contains("GRASS"):
				return Surface.GRASS
			elif mat_name.contains("WATER"):
				return Surface.WATER

	return Surface.CONCRETE


## Play a random footstep sound for the given surface type.
func play_footstep(surface: Surface) -> void:
	if _audio_player == null:
		return

	var sounds: Array = _footstep_sounds.get(surface, []) as Array
	if sounds.is_empty():
		return

	var sound: AudioStream = sounds[randi() % sounds.size()] as AudioStream
	if sound:
		_audio_player.stream = sound
		_audio_player.pitch_scale = randf_range(0.9, 1.1)  # Slight variation
		_audio_player.play()


## Convenience: detect current surface and play matching footstep.
func play_current_footstep() -> void:
	var surface: Surface = get_current_surface()
	play_footstep(surface)


func _load_sounds() -> void:
	_footstep_sounds[Surface.CONCRETE] = _try_load_streams(_concrete_paths)
	_footstep_sounds[Surface.WOOD] = _try_load_streams(_wood_paths)
	_footstep_sounds[Surface.METAL] = _try_load_streams(_metal_paths)
	_footstep_sounds[Surface.DIRT] = _try_load_streams(_dirt_paths)
	_footstep_sounds[Surface.GRASS] = _try_load_streams(_grass_paths)
	_footstep_sounds[Surface.WATER] = _try_load_streams(_water_paths)


func _try_load_streams(paths: Array[String]) -> Array:
	var streams: Array = []
	for path: String in paths:
		if ResourceLoader.exists(path):
			var stream: AudioStream = load(path) as AudioStream
			if stream:
				streams.append(stream)
	return streams
