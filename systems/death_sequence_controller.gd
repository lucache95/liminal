extends Node

## Orchestrates the ~3.5s death sequence when the monster catches the player.
## Intercepts player_died, runs camera lurch + shader crank + audio warp,
## then triggers game_ended for the death screen.
##
## Per user decision: player never sees the monster clearly. Camera lurches
## but stays disoriented. Audio: heartbeat accelerates to peak, then cuts
## to silence with a ringing tone. Visuals: crank existing PostProcessController
## shaders to extreme (no separate death shader).

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
const SEQUENCE_DURATION: float = 3.5
const PHASE_1_DURATION: float = 1.0   ## Camera lurch + shader ramp start
const PHASE_2_DURATION: float = 1.5   ## Escalating distortion + audio warp
const PHASE_3_DURATION: float = 1.0   ## Blackout + silence

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------
var _is_playing: bool = false
var _death_tween: Tween
var _ringing_player: AudioStreamPlayer

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------
func _ready() -> void:
	EventBus.player_died.connect(_on_player_died)
	# Create a dedicated AudioStreamPlayer for the ringing tone
	_ringing_player = AudioStreamPlayer.new()
	_ringing_player.bus = &"SFX"
	_ringing_player.volume_db = -80.0
	add_child(_ringing_player)


func _on_player_died() -> void:
	if _is_playing:
		return
	_is_playing = true
	EventBus.death_sequence_started.emit()

	# Lock player input
	var player: CharacterBody3D = get_tree().get_first_node_in_group(&"player")
	if player:
		player.set_physics_process(false)
		player.set_process(false)
		player.set_process_input(false)

	# Find PostProcessController
	var post_process: PostProcessController = get_tree().get_first_node_in_group(&"post_process") as PostProcessController
	# Find PlayerCamera for trauma
	var camera: Node = null
	if player:
		camera = player.find_child("PlayerCamera", true, false)
		if camera == null:
			camera = player.find_child("Camera3D", true, false)

	# Build the tween chain
	_death_tween = create_tween()
	_death_tween.set_parallel(false)

	# --- Phase 1 (0-1.0s): Camera lurch + shader ramp start ---
	_death_tween.tween_callback(func() -> void:
		# Camera trauma: strong initial lurch
		if camera and camera.has_method("add_trauma"):
			camera.add_trauma(0.8)
		# Start ramping shaders
		if post_process:
			post_process.set_death_intensity(0.3)
		# Ramp heartbeat volume to max (uses heartbeat_layer from Plan 06-02)
		if AudioManager.heartbeat_layer:
			AudioManager.heartbeat_layer.volume_db = -3.0
		if AudioManager.drone_layer:
			AudioManager.drone_layer.volume_db = -6.0
	)

	# Smooth shader ramp over Phase 1
	if post_process:
		_death_tween.tween_method(post_process.set_death_intensity, 0.3, 0.6, PHASE_1_DURATION)
	else:
		_death_tween.tween_interval(PHASE_1_DURATION)

	# --- Phase 2 (1.0-2.5s): Escalating distortion + audio warp ---
	_death_tween.tween_callback(func() -> void:
		# More camera trauma
		if camera and camera.has_method("add_trauma"):
			camera.add_trauma(0.6)
		# Swap heartbeat to fast version for escalation
		var fast_hb_path: String = "res://assets/audio/sfx/heartbeat_fast.mp3"
		if ResourceLoader.exists(fast_hb_path) and AudioManager.heartbeat_layer:
			AudioManager.heartbeat_layer.stream = load(fast_hb_path)
			AudioManager.heartbeat_layer.volume_db = 0.0
			AudioManager.heartbeat_layer.play()
	)

	if post_process:
		_death_tween.tween_method(post_process.set_death_intensity, 0.6, 1.0, PHASE_2_DURATION)
	else:
		_death_tween.tween_interval(PHASE_2_DURATION)

	# --- Phase 3 (2.5-3.5s): Blackout + silence with ringing ---
	_death_tween.tween_callback(func() -> void:
		# Kill all audio abruptly -- the silence IS the horror
		if AudioManager.heartbeat_layer:
			AudioManager.heartbeat_layer.volume_db = -80.0
		if AudioManager.drone_layer:
			AudioManager.drone_layer.volume_db = -80.0
		if AudioManager.sanity_layer:
			AudioManager.sanity_layer.volume_db = -80.0
		# Fade ambient layers
		if AudioManager.base_layer:
			AudioManager.base_layer.volume_db = -40.0
		if AudioManager.weather_layer:
			AudioManager.weather_layer.volume_db = -40.0

		# Play ringing tone (high-pitched tinnitus)
		# Use radio_static.mp3 as stand-in if no dedicated ringing file exists
		var ring_path: String = "res://assets/audio/sfx/radio_static.mp3"
		if ResourceLoader.exists(ring_path):
			_ringing_player.stream = load(ring_path)
			_ringing_player.volume_db = -12.0
			_ringing_player.play()
	)

	_death_tween.tween_interval(PHASE_3_DURATION)

	# --- Finish: trigger game_ended ---
	_death_tween.tween_callback(_finish_sequence)


func _finish_sequence() -> void:
	_is_playing = false
	# Stop ringing
	_ringing_player.stop()

	# Reset PostProcessController death flag
	var post_process: PostProcessController = get_tree().get_first_node_in_group(&"post_process") as PostProcessController
	if post_process:
		post_process._death_sequence_active = false

	EventBus.death_sequence_finished.emit()
	# NOW trigger game_ended so DeathScreen can show
	GameManager.end_run("caught")
