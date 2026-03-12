class_name PostProcessController
extends CanvasLayer
## Manages all post-processing shaders. Controls vignette, chromatic aberration,
## film grain, screen distortion, desaturation, and screen breathing based on
## game tension level and player sanity.

# --------------------------------------------------------------------------- #
# Node references
# --------------------------------------------------------------------------- #

@onready var desaturation_rect: ColorRect = $DesaturationRect
@onready var vignette_rect: ColorRect = $VignetteRect
@onready var aberration_rect: ColorRect = $AberrationRect
@onready var grain_rect: ColorRect = $GrainRect
@onready var distortion_rect: ColorRect = $DistortionRect
@onready var breathing_rect: ColorRect = $BreathingRect

# --------------------------------------------------------------------------- #
# State
# --------------------------------------------------------------------------- #

var _current_sanity: float = 1.0
var _current_tension: float = 0.0
var _distortion_tween: Tween
var _hallucination_timer: Timer = null
var _hallucination_cooldown: float = 0.0
var _death_sequence_active: bool = false

# --------------------------------------------------------------------------- #
# Lifecycle
# --------------------------------------------------------------------------- #

func _ready() -> void:
	add_to_group(&"post_process")
	EventBus.connect("tension_changed", _on_tension_changed)
	EventBus.connect("geometry_shifted", _on_geometry_shifted)
	EventBus.sanity_changed.connect(_on_sanity_changed)

	# Create hallucination flash timer
	_hallucination_timer = Timer.new()
	_hallucination_timer.one_shot = true
	_hallucination_timer.timeout.connect(_on_hallucination_tick)
	add_child(_hallucination_timer)

	# Set initial state
	set_tension(0.0)
	set_sanity(1.0)

# --------------------------------------------------------------------------- #
# Tension
# --------------------------------------------------------------------------- #

func set_tension(value: float) -> void:
	if _death_sequence_active:
		return
	value = clampf(value, 0.0, 1.0)
	_current_tension = value

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

	_apply_combined_effects()

# --------------------------------------------------------------------------- #
# Sanity (3-tier escalating effects)
# --------------------------------------------------------------------------- #

func set_sanity(value: float) -> void:
	if _death_sequence_active:
		return
	_current_sanity = clampf(value, 0.0, 1.0)
	var dread: float = 1.0 - _current_sanity  # 0 = sane, 1 = insane

	# Tier 1 - Mild (dread > 0.3, i.e. sanity < 0.7): desaturation + grain boost
	if desaturation_rect:
		var desat_mat: ShaderMaterial = desaturation_rect.material as ShaderMaterial
		if desat_mat:
			var sat: float = 1.0
			if dread > 0.3:
				sat = lerpf(1.0, 0.4, (dread - 0.3) / 0.7)
			desat_mat.set_shader_parameter(&"saturation", sat)

	# Tier 2 - Medium (dread > 0.5, i.e. sanity < 0.5): screen breathing
	if breathing_rect:
		var breath_mat: ShaderMaterial = breathing_rect.material as ShaderMaterial
		if breath_mat:
			var breath_str: float = 0.0
			if dread > 0.5:
				breath_str = lerpf(0.0, 0.03, (dread - 0.5) * 2.0)
			breath_mat.set_shader_parameter(&"strength", breath_str)

	# Tier 3 - Severe (dread > 0.7, i.e. sanity < 0.3): hallucination flashes
	if dread > 0.7:
		if _hallucination_timer.is_stopped():
			var interval: float = lerpf(8.0, 3.0, (dread - 0.7) / 0.3)
			_hallucination_timer.start(interval)
	else:
		_hallucination_timer.stop()

	_apply_combined_effects()

# --------------------------------------------------------------------------- #
# Combined effects (sanity amplifies tension)
# --------------------------------------------------------------------------- #

func _apply_combined_effects() -> void:
	# At low sanity, tension effects are amplified up to 50%
	var sanity_amp: float = lerpf(1.0, 1.5, 1.0 - _current_sanity)

	# Re-apply vignette with amplification
	var vignette_mat: ShaderMaterial = vignette_rect.material as ShaderMaterial
	if vignette_mat:
		var base_intensity: float = lerpf(0.3, 0.7, _current_tension)
		vignette_mat.set_shader_parameter(&"intensity", minf(base_intensity * sanity_amp, 1.0))

	# Re-apply aberration with amplification
	var aberration_mat: ShaderMaterial = aberration_rect.material as ShaderMaterial
	if aberration_mat:
		var base_aberration: float = 0.0
		if _current_tension > 0.5:
			base_aberration = lerpf(0.0, 0.03, (_current_tension - 0.5) * 2.0)
		aberration_mat.set_shader_parameter(&"strength", minf(base_aberration * sanity_amp, 0.06))

	# Re-apply grain with sanity boost
	var grain_mat: ShaderMaterial = grain_rect.material as ShaderMaterial
	if grain_mat:
		var base_grain: float = lerpf(0.03, 0.12, _current_tension)
		var dread: float = 1.0 - _current_sanity
		var sanity_grain_boost: float = 0.0
		if dread > 0.3:
			sanity_grain_boost = lerpf(0.0, 0.08, (dread - 0.3) / 0.7)
		grain_mat.set_shader_parameter(&"grain_amount", minf(base_grain + sanity_grain_boost, 0.25))

	# Re-apply distortion with amplification + sanity baseline at severe dread
	var distortion_mat: ShaderMaterial = distortion_rect.material as ShaderMaterial
	if distortion_mat:
		var base_distortion: float = 0.0
		if _current_tension > 0.8:
			base_distortion = lerpf(0.0, 0.04, (_current_tension - 0.8) * 5.0)
		var dread_val: float = 1.0 - _current_sanity
		var sanity_distortion_baseline: float = 0.0
		if dread_val > 0.7:
			sanity_distortion_baseline = lerpf(0.0, 0.02, (dread_val - 0.7) / 0.3)
		distortion_mat.set_shader_parameter(&"strength", minf((base_distortion * sanity_amp) + sanity_distortion_baseline, 0.08))

# --------------------------------------------------------------------------- #
# Death sequence
# --------------------------------------------------------------------------- #

## Sets all shader parameters to extreme death values. Called by DeathSequenceController.
## [param intensity] ranges from 0.0 to 1.0, where 1.0 is full death distortion.
func set_death_intensity(intensity: float) -> void:
	_death_sequence_active = true
	# Vignette: ramp from current to near-blackout
	var vignette_mat: ShaderMaterial = vignette_rect.material as ShaderMaterial
	if vignette_mat:
		vignette_mat.set_shader_parameter(&"intensity", lerpf(0.5, 1.5, intensity))
	# Chromatic aberration: extreme
	var aberration_mat: ShaderMaterial = aberration_rect.material as ShaderMaterial
	if aberration_mat:
		aberration_mat.set_shader_parameter(&"strength", lerpf(0.01, 0.15, intensity))
	# Film grain: maximum (uses grain_amount parameter)
	var grain_mat: ShaderMaterial = grain_rect.material as ShaderMaterial
	if grain_mat:
		grain_mat.set_shader_parameter(&"grain_amount", lerpf(0.1, 0.5, intensity))
	# Distortion: extreme warp
	var distortion_mat: ShaderMaterial = distortion_rect.material as ShaderMaterial
	if distortion_mat:
		distortion_mat.set_shader_parameter(&"strength", lerpf(0.02, 0.15, intensity))
	# Desaturation: full grayscale at peak
	var desat_mat: ShaderMaterial = desaturation_rect.material as ShaderMaterial
	if desat_mat:
		desat_mat.set_shader_parameter(&"saturation", lerpf(0.5, 0.0, intensity))
	# Breathing: extreme pulsing
	var breath_mat: ShaderMaterial = breathing_rect.material as ShaderMaterial
	if breath_mat:
		breath_mat.set_shader_parameter(&"strength", lerpf(0.01, 0.04, intensity))

# --------------------------------------------------------------------------- #
# Hallucination flash
# --------------------------------------------------------------------------- #

func _on_hallucination_tick() -> void:
	flash_distortion(0.3)
	var dread: float = 1.0 - _current_sanity
	if dread > 0.7:
		var t: float = (dread - 0.7) / 0.3
		var min_interval: float = lerpf(6.0, 2.0, t)
		var max_interval: float = lerpf(8.0, 3.0, t)
		_hallucination_timer.start(randf_range(min_interval, max_interval))

# --------------------------------------------------------------------------- #
# Distortion flash
# --------------------------------------------------------------------------- #

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

# --------------------------------------------------------------------------- #
# Signal callbacks
# --------------------------------------------------------------------------- #

func _on_tension_changed(value: float) -> void:
	set_tension(value)


func _on_geometry_shifted(_node_path: NodePath) -> void:
	flash_distortion()


func _on_sanity_changed(value: float) -> void:
	set_sanity(value)
