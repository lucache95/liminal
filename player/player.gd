class_name Player
extends CharacterBody3D
## First-person player controller with movement, sprint, crouch, head bob, and footsteps.

# --- Exports ---
@export_group("Movement")
@export var walk_speed: float = 4.0
@export var sprint_speed: float = 7.0
@export var crouch_speed: float = 2.0
@export var jump_velocity: float = 4.5
@export var mouse_sensitivity: float = 0.002
@export var gravity_multiplier: float = 1.0

@export_group("Stamina")
@export var max_stamina: float = 100.0
@export var stamina_drain_rate: float = 20.0
@export var stamina_regen_rate: float = 10.0

# --- State ---
var current_stamina: float = 100.0
var is_sprinting: bool = false
var is_crouching: bool = false
var current_speed: float = 4.0

# Head bob
var _head_bob_time: float = 0.0
const HEAD_BOB_AMPLITUDE: float = 0.03
const HEAD_BOB_WALK_FREQ: float = 2.4
const HEAD_BOB_SPRINT_FREQ: float = 3.4
const HEAD_BOB_CROUCH_FREQ: float = 1.6

# Crouch lerp
const STAND_HEIGHT: float = 1.8
const CROUCH_HEIGHT: float = 1.0
const HEAD_STAND_Y: float = 1.6
const HEAD_CROUCH_Y: float = 0.8
const CROUCH_LERP_SPEED: float = 10.0

# Footstep timing
var _footstep_timer: float = 0.0
const FOOTSTEP_WALK_INTERVAL: float = 0.5
const FOOTSTEP_SPRINT_INTERVAL: float = 0.35
const FOOTSTEP_CROUCH_INTERVAL: float = 0.7

# Sound emission intensities
const SOUND_WALK_INTENSITY: float = 0.5
const SOUND_SPRINT_INTENSITY: float = 1.0
const SOUND_CROUCH_INTENSITY: float = 0.15

# Gravity
var _gravity: float = 0.0

# --- Node References ---
@onready var head: Node3D = $Head
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var crouch_shape: CollisionShape3D = $CrouchShape
@onready var footstep_system: RayCast3D = $FootstepRay
@onready var footstep_audio: AudioStreamPlayer3D = $FootstepAudio


func _ready() -> void:
	add_to_group(&"player")
	_gravity = ProjectSettings.get_setting("physics/3d/default_gravity") * gravity_multiplier
	current_stamina = max_stamina


func _physics_process(delta: float) -> void:
	_apply_gravity(delta)
	_handle_jump()
	_handle_sprint(delta)
	_handle_crouch(delta)
	_handle_movement(delta)
	move_and_slide()
	_handle_head_bob(delta)
	_handle_footsteps(delta)


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta


func _handle_jump() -> void:
	if Input.is_action_just_pressed(&"interact"):
		pass  # interact is handled by interaction_system.gd
	if is_on_floor() and Input.is_action_just_pressed(&"jump") and not is_crouching:
		velocity.y = jump_velocity


func _handle_sprint(delta: float) -> void:
	var wants_sprint: bool = Input.is_action_pressed(&"sprint")
	if wants_sprint and current_stamina > 0.0 and not is_crouching and is_on_floor():
		is_sprinting = true
		current_stamina = maxf(current_stamina - stamina_drain_rate * delta, 0.0)
		if current_stamina <= 0.0:
			is_sprinting = false
	else:
		is_sprinting = false
		if not wants_sprint or not is_sprinting:
			current_stamina = minf(current_stamina + stamina_regen_rate * delta, max_stamina)


func _handle_crouch(delta: float) -> void:
	var wants_crouch: bool = Input.is_action_pressed(&"crouch")
	is_crouching = wants_crouch

	var target_height: float = CROUCH_HEIGHT if is_crouching else STAND_HEIGHT
	var target_head_y: float = HEAD_CROUCH_Y if is_crouching else HEAD_STAND_Y

	# Lerp collision shape height
	var capsule: CapsuleShape3D = collision_shape.shape as CapsuleShape3D
	if capsule:
		capsule.height = lerpf(capsule.height, target_height, CROUCH_LERP_SPEED * delta)

	# Lerp head position
	head.position.y = lerpf(head.position.y, target_head_y, CROUCH_LERP_SPEED * delta)

	# Toggle crouch collision shapes
	collision_shape.disabled = is_crouching
	crouch_shape.disabled = not is_crouching


func _handle_movement(_delta: float) -> void:
	# Determine current speed
	if is_crouching:
		current_speed = crouch_speed
	elif is_sprinting:
		current_speed = sprint_speed
	else:
		current_speed = walk_speed

	# Get input direction relative to player facing
	var input_dir: Vector2 = Input.get_vector(
		&"move_left", &"move_right",
		&"move_forward", &"move_backward"
	)
	var direction: Vector3 = (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()

	if direction != Vector3.ZERO:
		velocity.x = direction.x * current_speed
		velocity.z = direction.z * current_speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, current_speed)
		velocity.z = move_toward(velocity.z, 0.0, current_speed)


func _handle_head_bob(delta: float) -> void:
	var horizontal_velocity: Vector3 = Vector3(velocity.x, 0.0, velocity.z)
	if horizontal_velocity.length() < 0.5 or not is_on_floor():
		# Reset bob smoothly when standing still or airborne
		_head_bob_time = 0.0
		return

	var freq: float = HEAD_BOB_WALK_FREQ
	if is_sprinting:
		freq = HEAD_BOB_SPRINT_FREQ
	elif is_crouching:
		freq = HEAD_BOB_CROUCH_FREQ

	_head_bob_time += delta * freq
	var bob_offset: float = sin(_head_bob_time * TAU) * HEAD_BOB_AMPLITUDE

	# Apply bob to the camera (child of Head), not the head itself (head Y is for crouch)
	var camera: Camera3D = head.get_node("Camera3D") as Camera3D
	if camera:
		camera.position.y = bob_offset


func _handle_footsteps(delta: float) -> void:
	var horizontal_velocity: Vector3 = Vector3(velocity.x, 0.0, velocity.z)
	if horizontal_velocity.length() < 0.5 or not is_on_floor():
		_footstep_timer = 0.0
		return

	var interval: float = FOOTSTEP_WALK_INTERVAL
	var intensity: float = SOUND_WALK_INTENSITY
	if is_sprinting:
		interval = FOOTSTEP_SPRINT_INTERVAL
		intensity = SOUND_SPRINT_INTENSITY
	elif is_crouching:
		interval = FOOTSTEP_CROUCH_INTERVAL
		intensity = SOUND_CROUCH_INTENSITY

	_footstep_timer += delta
	if _footstep_timer >= interval:
		_footstep_timer -= interval
		# Play footstep sound via FootstepSystem
		if footstep_system and footstep_system.has_method("play_current_footstep"):
			footstep_system.play_current_footstep()
		# Emit sound for AI detection
		EventBus.sound_emitted.emit(global_position, intensity, "footstep")


## Returns the stamina as a percentage 0.0 - 1.0.
func get_stamina_percent() -> float:
	return current_stamina / max_stamina
