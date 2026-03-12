extends Node
## Manages game state, run configuration, pause, and the run timer.

# ---------------------------------------------------------------------------
# Enums
# ---------------------------------------------------------------------------

enum GameState { MENU, PLAYING, PAUSED, GAME_OVER }

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const DEFAULT_MAX_RUN_TIME: float = 2400.0 # 40 minutes
const TOWN_LEVEL_PATH: String = "res://levels/town/town.tscn"

# ---------------------------------------------------------------------------
# Properties
# ---------------------------------------------------------------------------

var current_seed: int = 0
var is_paused: bool = false
var run_active: bool = false
var elapsed_time: float = 0.0
var max_run_time: float = DEFAULT_MAX_RUN_TIME
var current_state: GameState = GameState.MENU

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	EventBus.connect("all_objectives_completed", _on_all_objectives_completed)
	EventBus.connect("player_died", _on_player_died)


func _process(delta: float) -> void:
	if not run_active:
		return
	if current_state != GameState.PLAYING:
		return

	elapsed_time += delta
	if elapsed_time >= max_run_time:
		end_run("time")


func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause"):
		if current_state == GameState.PLAYING:
			pause_game()
		elif current_state == GameState.PAUSED:
			resume_game()

# ---------------------------------------------------------------------------
# Run control
# ---------------------------------------------------------------------------

func start_new_run(custom_seed: int = -1) -> void:
	if custom_seed < 0:
		current_seed = randi()
	else:
		current_seed = custom_seed

	seed(current_seed)

	elapsed_time = 0.0
	run_active = true
	is_paused = false
	current_state = GameState.PLAYING
	get_tree().paused = false

	EventBus.emit_signal("game_started", current_seed)

	# Initialize ambient audio layers
	_setup_ambient_audio()

	SceneManager.change_scene(TOWN_LEVEL_PATH)


func end_run(reason: String) -> void:
	run_active = false
	current_state = GameState.GAME_OVER
	EventBus.emit_signal("game_ended", reason)

# ---------------------------------------------------------------------------
# Pause
# ---------------------------------------------------------------------------

func pause_game() -> void:
	if current_state != GameState.PLAYING:
		return
	is_paused = true
	current_state = GameState.PAUSED
	get_tree().paused = true


func resume_game() -> void:
	if current_state != GameState.PAUSED:
		return
	is_paused = false
	current_state = GameState.PLAYING
	get_tree().paused = false

# ---------------------------------------------------------------------------
# Signal callbacks
# ---------------------------------------------------------------------------

func _on_all_objectives_completed() -> void:
	end_run("escape")


func _on_player_died() -> void:
	end_run("caught")

# ---------------------------------------------------------------------------
# Ambient audio
# ---------------------------------------------------------------------------

func _setup_ambient_audio() -> void:
	# Base layer: horror drone (randomly chosen)
	var drone_paths: Array[String] = [
		"res://assets/audio/sfx/horror_drone_01.mp3",
		"res://assets/audio/sfx/horror_drone_02.mp3",
	]
	var drone_path: String = drone_paths[randi() % drone_paths.size()]
	if ResourceLoader.exists(drone_path):
		var drone: AudioStream = load(drone_path)
		AudioManager.crossfade_layer("base_layer", drone, 3.0)

	# Weather layer: wind loop
	var wind_path: String = "res://assets/audio/ambience/wind_loop.wav"
	if ResourceLoader.exists(wind_path):
		var wind: AudioStream = load(wind_path)
		AudioManager.crossfade_layer("weather_layer", wind, 4.0)

	# Tension layer: heartbeat (volume controlled by tension_changed signal)
	var heartbeat_path: String = "res://assets/audio/sfx/heartbeat_tension.mp3"
	if ResourceLoader.exists(heartbeat_path):
		var heartbeat: AudioStream = load(heartbeat_path)
		AudioManager.tension_layer.stream = heartbeat
