class_name GameManager
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
	EventBus.all_objectives_completed.connect(_on_all_objectives_completed)
	EventBus.player_died.connect(_on_player_died)


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

	EventBus.game_started.emit(current_seed)
	SceneManager.change_scene(TOWN_LEVEL_PATH)


func end_run(reason: String) -> void:
	run_active = false
	current_state = GameState.GAME_OVER
	EventBus.game_ended.emit(reason)

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
