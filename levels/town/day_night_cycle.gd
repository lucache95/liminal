class_name DayNightCycle
extends Node
## Drives the day/night cycle from warm dusk to near-total darkness.
## Uses Gradient resources for sky colors, a Curve resource for light energy,
## and a Tween-based flicker-and-die system for degrading street lamps.
## SanityManager discovers this node via the "day_night_cycle" group.

# ---------------------------------------------------------------------------
# Exports
# ---------------------------------------------------------------------------

@export var world_env: WorldEnvironment
@export var sun_light: DirectionalLight3D
@export var run_duration: float = 2400.0

# ---------------------------------------------------------------------------
# Public state
# ---------------------------------------------------------------------------

## Current ambient light level (0.0 = total darkness, 1.0 = bright dusk).
## Read by SanityManager to drive darkness-based sanity drain.
var ambient_light_level: float = 1.0

# ---------------------------------------------------------------------------
# Private state
# ---------------------------------------------------------------------------

var _elapsed: float = 0.0

var _sky_top_gradient: Gradient
var _sky_horizon_gradient: Gradient
var _ground_color_gradient: Gradient
var _light_energy_curve: Curve

var _degradable_lights: Array[OmniLight3D] = []
var _lights_degraded: int = 0

# ---------------------------------------------------------------------------
# Color constants
# ---------------------------------------------------------------------------

const DUSK_LIGHT_COLOR: Color = Color(1.0, 0.9, 0.7)
const MOON_LIGHT_COLOR: Color = Color(0.3, 0.35, 0.5)

const SUN_START_ANGLE: float = -15.0
const SUN_END_ANGLE: float = -90.0

const AMBIENT_ENERGY_START: float = 0.3
const AMBIENT_ENERGY_END: float = 0.02

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	_setup_gradients()
	_setup_curves()
	_setup_degrading_lights()
	add_to_group(&"day_night_cycle")


func _process(delta: float) -> void:
	if not GameManager.run_active:
		return
	if GameManager.current_state != GameManager.GameState.PLAYING:
		return

	_elapsed += delta
	var t: float = clampf(_elapsed / run_duration, 0.0, 1.0)

	_update_sky(t)
	_update_lighting(t)
	_update_degrading_lights(t)

	EventBus.day_night_progress.emit(t)

# ---------------------------------------------------------------------------
# Sky
# ---------------------------------------------------------------------------

## Updates ProceduralSkyMaterial colors from gradient resources.
func _update_sky(t: float) -> void:
	var sky_mat: ProceduralSkyMaterial = world_env.environment.sky.sky_material
	sky_mat.sky_top_color = _sky_top_gradient.sample(t)
	sky_mat.sky_horizon_color = _sky_horizon_gradient.sample(t)
	sky_mat.ground_bottom_color = _ground_color_gradient.sample(t)

# ---------------------------------------------------------------------------
# Lighting
# ---------------------------------------------------------------------------

## Updates DirectionalLight3D energy/color and ambient light from curve/lerp.
func _update_lighting(t: float) -> void:
	var energy: float = _light_energy_curve.sample(t)
	sun_light.light_energy = energy
	sun_light.light_color = DUSK_LIGHT_COLOR.lerp(MOON_LIGHT_COLOR, t)
	sun_light.rotation_degrees.x = lerpf(SUN_START_ANGLE, SUN_END_ANGLE, t)

	world_env.environment.ambient_light_energy = lerpf(AMBIENT_ENERGY_START, AMBIENT_ENERGY_END, t)

	ambient_light_level = energy

# ---------------------------------------------------------------------------
# Degrading lights
# ---------------------------------------------------------------------------

## Collects lights in the "degradable_light" group and shuffles them.
func _setup_degrading_lights() -> void:
	for node: Node in get_tree().get_nodes_in_group(&"degradable_light"):
		if node is OmniLight3D:
			_degradable_lights.append(node as OmniLight3D)
	_degradable_lights.shuffle()


## Progressively kills street lamps between t=0.3 and t=0.9.
func _update_degrading_lights(t: float) -> void:
	if _degradable_lights.is_empty():
		return
	if t < 0.3:
		return

	var degrade_progress: float = clampf((t - 0.3) / 0.6, 0.0, 1.0)
	var target_dead: int = int(degrade_progress * _degradable_lights.size())

	while _lights_degraded < target_dead and _lights_degraded < _degradable_lights.size():
		var light: OmniLight3D = _degradable_lights[_lights_degraded]
		_flicker_and_die(light)
		_lights_degraded += 1


## Flickers a light rapidly then fades it to zero and hides it.
func _flicker_and_die(light: OmniLight3D) -> void:
	var tween: Tween = create_tween()
	var original_energy: float = light.light_energy

	# 5 rapid flickers
	for i: int in range(5):
		tween.tween_property(light, "light_energy", randf_range(0.0, original_energy), 0.15)

	# Fade to zero and hide
	tween.tween_property(light, "light_energy", 0.0, 0.3)
	tween.tween_callback(func() -> void:
		light.visible = false
		EventBus.light_degraded.emit(light.get_path())
	)

# ---------------------------------------------------------------------------
# Gradient / Curve setup
# ---------------------------------------------------------------------------

## Creates Gradient resources for sky color transitions.
func _setup_gradients() -> void:
	# Sky top: warm orange -> deep blue -> near-black
	_sky_top_gradient = Gradient.new()
	_sky_top_gradient.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	_sky_top_gradient.colors = PackedColorArray([
		Color(0.95, 0.55, 0.25),
		Color(0.05, 0.05, 0.15),
		Color(0.01, 0.01, 0.03),
	])

	# Sky horizon: pink-orange -> dark blue-grey -> near-black
	_sky_horizon_gradient = Gradient.new()
	_sky_horizon_gradient.offsets = PackedFloat32Array([0.0, 0.6, 1.0])
	_sky_horizon_gradient.colors = PackedColorArray([
		Color(1.0, 0.6, 0.4),
		Color(0.1, 0.1, 0.2),
		Color(0.02, 0.02, 0.05),
	])

	# Ground: warm brown -> dark
	_ground_color_gradient = Gradient.new()
	_ground_color_gradient.offsets = PackedFloat32Array([0.0, 0.8, 1.0])
	_ground_color_gradient.colors = PackedColorArray([
		Color(0.3, 0.2, 0.1),
		Color(0.02, 0.02, 0.03),
		Color(0.02, 0.02, 0.03),
	])


## Creates a Curve resource for front-loaded light energy falloff.
func _setup_curves() -> void:
	_light_energy_curve = Curve.new()
	_light_energy_curve.add_point(Vector2(0.0, 1.0))
	_light_energy_curve.add_point(Vector2(0.2, 0.8))
	_light_energy_curve.add_point(Vector2(0.5, 0.3))
	_light_energy_curve.add_point(Vector2(0.8, 0.05))
	_light_energy_curve.add_point(Vector2(1.0, 0.02))
