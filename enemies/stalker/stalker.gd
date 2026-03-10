extends CharacterBody3D
## Main controller for the Stalker monster.
## Manages navigation, state machine, sensors, and shared blackboard data.

const GRAVITY: float = 9.8

@export var config: MonsterConfig
@export var patrol_points: Array[Marker3D] = []

## Shared blackboard for inter-state communication.
var blackboard: Dictionary = {
	"last_known_position": Vector3.ZERO,
	"alert_level": 0.0,       # 0.0 to 1.0
	"player_visible": false,
	"current_speed": 0.0,
	"time_since_player_seen": 0.0,
}

@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D
@onready var state_machine: StateMachine = $StateMachine
@onready var sight_sensor: Node3D = $SightSensor
@onready var hearing_sensor: Node3D = $HearingSensor
@onready var audio_player: AudioStreamPlayer3D = $AudioPlayer

var _player: Node3D


func _ready() -> void:
	add_to_group(&"monster")
	_player = get_tree().get_first_node_in_group(&"player")

	# Initialize hearing sensor with our config
	if hearing_sensor.has_method(&"initialize"):
		hearing_sensor.call(&"initialize", config)

	# NavigationAgent3D setup
	nav_agent.path_desired_distance = 0.5
	nav_agent.target_desired_distance = 1.0
	nav_agent.avoidance_enabled = true

	# Connect navigation signal
	nav_agent.velocity_computed.connect(_on_velocity_computed)


func _physics_process(delta: float) -> void:
	# Apply gravity
	if not is_on_floor():
		velocity.y -= GRAVITY * delta

	# Try to find player if reference is lost
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group(&"player")

	# Update sight detection
	_update_sight_check()

	# Navigate toward current target
	_navigate(delta)


## Set the navigation target to a world position.
func move_to_point(target: Vector3) -> void:
	nav_agent.target_position = target


## Returns the movement speed based on the current state machine state.
func get_movement_speed() -> float:
	if config == null:
		return 0.0

	var state_name: String = ""
	if state_machine and state_machine.current_state:
		state_name = state_machine.current_state.name.to_lower()

	match state_name:
		"chasestate":
			return config.chase_speed
		"investigatestate":
			return config.investigate_speed
		"patrolstate":
			return config.patrol_speed
		"searchstate":
			return config.investigate_speed
		_:
			return 0.0


## Returns a reference to the player node if available.
func get_player() -> Node3D:
	return _player


## Returns true if the navigation agent has reached its target.
func has_reached_target() -> bool:
	return nav_agent.is_navigation_finished()


## Returns the forward direction of the monster (negative Z in local space).
func get_forward_direction() -> Vector3:
	return -global_transform.basis.z.normalized()


## Smoothly rotates toward a target position over time.
func look_toward(target_pos: Vector3, delta: float, turn_speed: float = 3.0) -> void:
	var direction: Vector3 = (target_pos - global_position).normalized()
	direction.y = 0.0
	if direction.length_squared() < 0.001:
		return
	var target_basis: Basis = Basis.looking_at(direction, Vector3.UP)
	global_transform.basis = global_transform.basis.slerp(target_basis, turn_speed * delta)


func _update_sight_check() -> void:
	if _player == null or config == null:
		blackboard["player_visible"] = false
		return

	var can_see: bool = sight_sensor.can_see_player(
		global_position,
		get_forward_direction(),
		_player,
		config
	)
	blackboard["player_visible"] = can_see

	if can_see:
		blackboard["last_known_position"] = _player.global_position
		blackboard["time_since_player_seen"] = 0.0


func _navigate(delta: float) -> void:
	if nav_agent.is_navigation_finished():
		# Stop horizontal movement when arrived
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		return

	var speed: float = get_movement_speed()
	blackboard["current_speed"] = speed

	var next_path_pos: Vector3 = nav_agent.get_next_path_position()
	var direction: Vector3 = (next_path_pos - global_position).normalized()

	# Only apply horizontal movement; gravity is handled separately
	var desired_velocity: Vector3 = direction * speed
	desired_velocity.y = velocity.y

	if nav_agent.avoidance_enabled:
		nav_agent.velocity = desired_velocity
	else:
		velocity = desired_velocity
		move_and_slide()

	# Rotate to face movement direction
	if speed > 0.1:
		look_toward(next_path_pos, delta)


func _on_velocity_computed(safe_velocity: Vector3) -> void:
	velocity = safe_velocity
	move_and_slide()
