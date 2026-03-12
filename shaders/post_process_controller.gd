class_name PostProcessController
extends CanvasLayer
## Manages all post-processing shaders. Controls vignette, chromatic aberration,
## film grain, and screen distortion based on game tension level.

@onready var vignette_rect: ColorRect = $VignetteRect
@onready var aberration_rect: ColorRect = $AberrationRect
@onready var grain_rect: ColorRect = $GrainRect
@onready var distortion_rect: ColorRect = $DistortionRect

var _distortion_tween: Tween


func _ready() -> void:
	EventBus.connect("tension_changed", _on_tension_changed)
	EventBus.connect("geometry_shifted", _on_geometry_shifted)
	# Set initial low-tension values
	set_tension(0.0)


func set_tension(value: float) -> void:
	value = clampf(value, 0.0, 1.0)

	# Vignette: always present, ramps from subtle to heavy
	var vignette_mat: ShaderMaterial = vignette_rect.material as ShaderMaterial
	if vignette_mat:
		vignette_mat.set_shader_parameter(&"intensity", lerpf(0.3, 0.7, value))

	# Chromatic aberration: only kicks in above 50% tension
	var aberration_mat: ShaderMaterial = aberration_rect.material as ShaderMaterial
	if aberration_mat:
		var aberration_strength: float = 0.0
		if value > 0.5:
			aberration_strength = lerpf(0.0, 0.03, (value - 0.5) * 2.0)
		aberration_mat.set_shader_parameter(&"strength", aberration_strength)

	# Film grain: always present, ramps up
	var grain_mat: ShaderMaterial = grain_rect.material as ShaderMaterial
	if grain_mat:
		grain_mat.set_shader_parameter(&"grain_amount", lerpf(0.03, 0.12, value))

	# Distortion: only kicks in above 80% tension
	var distortion_mat: ShaderMaterial = distortion_rect.material as ShaderMaterial
	if distortion_mat:
		var distortion_strength: float = 0.0
		if value > 0.8:
			distortion_strength = lerpf(0.0, 0.04, (value - 0.8) * 5.0)
		distortion_mat.set_shader_parameter(&"strength", distortion_strength)


func flash_distortion(duration: float = 0.5) -> void:
	var distortion_mat: ShaderMaterial = distortion_rect.material as ShaderMaterial
	if not distortion_mat:
		push_error("PostProcessController: distortion material not found")
		return

	# Kill any running tween first
	if _distortion_tween and _distortion_tween.is_valid():
		_distortion_tween.kill()

	# Store current value so we can restore it
	var current: float = distortion_mat.get_shader_parameter(&"strength")
	var peak: float = 0.06

	_distortion_tween = create_tween()
	_distortion_tween.tween_method(
		func(val: float) -> void:
			distortion_mat.set_shader_parameter(&"strength", val),
		current,
		peak,
		duration * 0.2
	)
	_distortion_tween.tween_method(
		func(val: float) -> void:
			distortion_mat.set_shader_parameter(&"strength", val),
		peak,
		current,
		duration * 0.8
	)


func _on_tension_changed(value: float) -> void:
	set_tension(value)


func _on_geometry_shifted(_node_path: NodePath) -> void:
	flash_distortion()
