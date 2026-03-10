class_name PauseMenu
extends CanvasLayer
## Pause overlay that appears when the game is paused.
## Uses PROCESS_MODE_ALWAYS so it remains functional while the tree is paused.

# ---------------------------------------------------------------------------
# @onready references
# ---------------------------------------------------------------------------

@onready var overlay: ColorRect = %Overlay
@onready var menu_container: VBoxContainer = %MenuContainer
@onready var resume_button: Button = %ResumeButton
@onready var settings_button: Button = %SettingsButton
@onready var quit_to_menu_button: Button = %QuitToMenuButton

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const MAIN_MENU_PATH: String = "res://ui/main_menu/main_menu.tscn"

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_set_visible(false)

	resume_button.pressed.connect(_on_resume_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	quit_to_menu_button.pressed.connect(_on_quit_to_menu_pressed)


func _process(_delta: float) -> void:
	# Sync visibility with GameManager state.
	var should_show: bool = GameManager.current_state == GameManager.GameState.PAUSED
	if overlay.visible != should_show:
		_set_visible(should_show)

# ---------------------------------------------------------------------------
# Visibility
# ---------------------------------------------------------------------------

func _set_visible(show: bool) -> void:
	overlay.visible = show
	menu_container.visible = show
	if show:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		if GameManager.current_state == GameManager.GameState.PLAYING:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

# ---------------------------------------------------------------------------
# Button callbacks
# ---------------------------------------------------------------------------

func _on_resume_pressed() -> void:
	GameManager.resume_game()


func _on_settings_pressed() -> void:
	# Settings panel could be shown inline here in a future iteration.
	# For now this is a placeholder that could open a settings sub-panel.
	pass


func _on_quit_to_menu_pressed() -> void:
	GameManager.end_run("quit")
	get_tree().paused = false
	SceneManager.change_scene(MAIN_MENU_PATH)
