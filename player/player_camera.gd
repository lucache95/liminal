class_name PlayerCamera
extends Camera3D
## FPS camera controller with mouse look, FOV transitions, and trauma-based camera shake.

# --- Exports ---
@export var base_fov: float = 70.0

# --- Shake ---
var _trauma: float = 0.0
var _noise: FastNoiseLite
const MAX_SHAKE_OFFSET_DEG: float = 5.0
const TRAUMA_DECAY_RATE: float = 1.5

# --- FOV ---
var _target_fov: float = 70.0
var _fov_modifier: float = 0.0
var _fov_tween: Tween

# --- Noise sampling offset (avoids axis correlation) ---
var _noise_y_offset: float = 100.0
var _noise_z_offset: float = 200.0
var _shake_time: float = 0.0


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	fov = base_fov
	_target_fov = base_fov

	# Set up FastNoiseLite for shake
	_noise = FastNoiseLite.new()
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 2.0
	_noise.seed = randi()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var mouse_event: InputEventMouseMotion = event as InputEventMouseMotion
		# Rotate the player body (CharacterBody3D) on Y axis
		var player_body: Node3D = get_parent().get_parent() as Node3D
		if player_body:
			player_body.rotate_y(-mouse_event.relative.x * _get_sensitivity())
		# Rotate camera on X axis (look up/down)
		rotate_x(-mouse_event.relative.y * _get_sensitivity())
		rotation.x = clampf(rotation.x, deg_to_rad(-89.0), deg_to_rad(89.0))


func _process(delta: float) -> void:
	_update_fov(delta)
	_update_shake(delta)


func _update_fov(delta: float) -> void:
	var desired_fov: float = base_fov + _fov_modifier
	fov = lerpf(fov, desired_fov, 8.0 * delta)


func _update_shake(delta: float) -> void:
	if _trauma <= 0.0:
		return

	_shake_time += delta * 20.0
	var shake_amount: float = _trauma * _trauma  # Quadratic for natural feel

	var offset_x: float = _noise.get_noise_1d(_shake_time) * MAX_SHAKE_OFFSET_DEG * shake_amount
	var offset_y: float = _noise.get_noise_1d(_shake_time + _noise_y_offset) * MAX_SHAKE_OFFSET_DEG * shake_amount
	var offset_z: float = _noise.get_noise_1d(_shake_time + _noise_z_offset) * MAX_SHAKE_OFFSET_DEG * shake_amount * 0.5

	# Apply shake as additional rotation offset (converted to radians)
	rotation.x += deg_to_rad(offset_x) * delta * 10.0
	rotation.z = deg_to_rad(offset_z)  # Roll resets each frame, purely cosmetic

	# Keep vertical clamp intact after shake
	rotation.x = clampf(rotation.x, deg_to_rad(-89.0), deg_to_rad(89.0))

	# Decay trauma
	_trauma = maxf(_trauma - TRAUMA_DECAY_RATE * delta, 0.0)
	if _trauma <= 0.001:
		_trauma = 0.0
		rotation.z = 0.0  # Reset roll


## Add camera trauma for shake. Amount is clamped to 0.0 - 1.0.
func add_trauma(amount: float) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)


## Smoothly shift FOV by a modifier over a given duration. Use 0.0 to reset.
func set_fov_modifier(modifier: float, duration: float) -> void:
	if _fov_tween and _fov_tween.is_running():
		_fov_tween.kill()

	if duration <= 0.0:
		_fov_modifier = modifier
		return

	_fov_tween = create_tween()
	_fov_tween.tween_property(self, "_fov_modifier", modifier, duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)


func _get_sensitivity() -> float:
	var player: Node = get_parent().get_parent()
	if player and "mouse_sensitivity" in player:
		return player.mouse_sensitivity
	return 0.002
