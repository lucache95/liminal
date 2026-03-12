class_name WeatherManager
extends Node
## Manages weather presets (clear, foggy, rainy) for each run.
## Weather is deterministically selected from the run seed so the same seed
## always produces the same weather. Configures volumetric fog, ground fog
## plane, rain particles, and weather-specific audio.

# ---------------------------------------------------------------------------
# Enums
# ---------------------------------------------------------------------------

enum Weather { CLEAR, FOGGY, RAINY }

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var current_weather: Weather = Weather.CLEAR

var _rain_particles: GPUParticles3D = null
var _fog_ground_plane: MeshInstance3D = null
var _player: CharacterBody3D = null

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Select weather deterministically from [param run_seed] and apply it to [param env].
func apply_weather(run_seed: int, env: Environment) -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = run_seed
	current_weather = rng.randi_range(0, 2) as Weather

	match current_weather:
		Weather.CLEAR:
			_apply_clear(env)
		Weather.FOGGY:
			_apply_foggy(env)
		Weather.RAINY:
			_apply_rainy(env)

	var weather_name: String = Weather.keys()[current_weather].to_lower()
	EventBus.weather_set.emit(weather_name)

# ---------------------------------------------------------------------------
# Weather presets
# ---------------------------------------------------------------------------

## Clear weather — minimal atmospheric haze, long shadows, exposed feeling.
func _apply_clear(env: Environment) -> void:
	env.volumetric_fog_density = 0.005
	env.fog_density = 0.002

	# Audio: ambient crickets if available
	var audio_path: String = "res://assets/audio/ambience/crickets_night.ogg"
	if ResourceLoader.exists(audio_path):
		var stream: AudioStream = load(audio_path)
		AudioManager.crossfade_layer("weather_layer", stream, 2.0)


## Foggy weather — thick volumetric fog with rolling ground fog plane.
func _apply_foggy(env: Environment) -> void:
	env.volumetric_fog_density = 0.04
	env.fog_density = 0.03
	env.volumetric_fog_albedo = Color(0.15, 0.15, 0.18, 1.0)

	_create_fog_ground_plane()

	# Audio: heavy wind if available
	var audio_path: String = "res://assets/audio/ambience/wind_heavy.ogg"
	if ResourceLoader.exists(audio_path):
		var stream: AudioStream = load(audio_path)
		AudioManager.crossfade_layer("weather_layer", stream, 2.0)


## Rainy weather — rain particles, light mist, wet saturation boost.
func _apply_rainy(env: Environment) -> void:
	env.volumetric_fog_density = 0.02
	env.fog_density = 0.015
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.15

	_rain_particles = _setup_rain()
	add_child(_rain_particles)

	# Audio: heavy rain if available
	var audio_path: String = "res://assets/audio/ambience/rain_heavy.ogg"
	if ResourceLoader.exists(audio_path):
		var stream: AudioStream = load(audio_path)
		AudioManager.crossfade_layer("weather_layer", stream, 2.0)

# ---------------------------------------------------------------------------
# Rain particle system
# ---------------------------------------------------------------------------

## Create and return a GPUParticles3D configured as falling rain streaks.
func _setup_rain() -> GPUParticles3D:
	var particles: GPUParticles3D = GPUParticles3D.new()
	particles.name = "RainParticles"
	particles.amount = 2000
	particles.lifetime = 1.5
	particles.local_coords = false
	particles.visibility_aabb = AABB(Vector3(-30, -10, -30), Vector3(60, 30, 60))

	# Process material
	var mat: ParticleProcessMaterial = ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(25, 0.5, 25)
	mat.gravity = Vector3(0, -20, -2)
	mat.initial_velocity_min = 15.0
	mat.initial_velocity_max = 20.0
	mat.direction = Vector3(0, -1, 0)
	mat.spread = 5.0
	mat.scale_min = 0.02
	mat.scale_max = 0.04
	particles.process_material = mat

	# Draw pass — thin quad streaks
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(0.02, 0.3)

	var draw_mat: StandardMaterial3D = StandardMaterial3D.new()
	draw_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	draw_mat.albedo_color = Color(0.7, 0.75, 0.85, 0.3)
	draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	quad.material = draw_mat

	particles.draw_pass_1 = quad
	return particles

# ---------------------------------------------------------------------------
# Ground fog plane
# ---------------------------------------------------------------------------

## Create a large plane mesh with the fog_ground shader for rolling ground fog.
func _create_fog_ground_plane() -> void:
	_fog_ground_plane = MeshInstance3D.new()
	_fog_ground_plane.name = "FogGroundPlane"

	var plane_mesh: PlaneMesh = PlaneMesh.new()
	plane_mesh.size = Vector2(200, 200)
	_fog_ground_plane.mesh = plane_mesh

	var shader: Shader = load("res://shaders/fog_ground.gdshader")
	var shader_mat: ShaderMaterial = ShaderMaterial.new()
	shader_mat.shader = shader
	shader_mat.set_shader_parameter("density", 0.7)
	shader_mat.set_shader_parameter("height_falloff", 0.8)
	shader_mat.set_shader_parameter("fog_color", Color(0.6, 0.65, 0.72, 0.4))
	_fog_ground_plane.material_override = shader_mat

	_fog_ground_plane.position = Vector3(0, 0.5, 0)
	add_child(_fog_ground_plane)

# ---------------------------------------------------------------------------
# Per-frame updates
# ---------------------------------------------------------------------------

func _process(_delta: float) -> void:
	if _rain_particles == null:
		return

	# Track the player so rain follows them
	if _player == null:
		_player = get_tree().get_first_node_in_group(&"player")
	if _player != null:
		_rain_particles.global_position = _player.global_position + Vector3(0, 15, 0)
