class_name DeathScreen
extends CanvasLayer
## Game over screen displayed when the run ends.
## Fades in with contextual messaging based on the end reason.

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const MAIN_MENU_PATH: String = "res://ui/main_menu/main_menu.tscn"
const FADE_DURATION: float = 2.0

const DEATH_MESSAGES: Dictionary = {
	"caught": "YOU WERE FOUND",
	"escape": "YOU ESCAPED",
	"time": "TIME RAN OUT",
	"quit": "",
}

const DEATH_COLORS: Dictionary = {
	"caught": Color(0.6, 0.1, 0.1),
	"escape": Color(0.75, 0.75, 0.8),
	"time": Color(0.5, 0.4, 0.1),
	"quit": Color(0.7, 0.7, 0.75),
}

# ---------------------------------------------------------------------------
# @onready references
# ---------------------------------------------------------------------------

@onready var overlay: ColorRect = %DeathOverlay
@onready var content: VBoxContainer = %DeathContent
@onready var death_text: Label = %DeathText
@onready var retry_button: Button = %RetryButton
@onready var menu_button: Button = %MenuButton

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	overlay.color = Color(0.0, 0.0, 0.0, 0.0)
	content.modulate = Color(1.0, 1.0, 1.0, 0.0)
	overlay.visible = false
	content.visible = false

	retry_button.pressed.connect(_on_retry_pressed)
	menu_button.pressed.connect(_on_menu_pressed)
	EventBus.connect("game_ended", _on_game_ended)

# ---------------------------------------------------------------------------
# Game end handling
# ---------------------------------------------------------------------------

func _on_game_ended(reason: String) -> void:
	if reason == "quit":
		return

	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	var message: String = DEATH_MESSAGES.get(reason, "GAME OVER")
	var color: Color = DEATH_COLORS.get(reason, Color(0.7, 0.7, 0.75))

	death_text.text = message
	death_text.add_theme_color_override("font_color", color)

	overlay.visible = true
	content.visible = true

	# Fade in the dark overlay.
	var overlay_tween: Tween = create_tween()
	overlay_tween.tween_property(overlay, "color:a", 0.85, FADE_DURATION)

	# Fade in the text and buttons after a short delay.
	var content_tween: Tween = create_tween()
	content_tween.tween_interval(FADE_DURATION * 0.5)
	content_tween.tween_property(content, "modulate:a", 1.0, FADE_DURATION * 0.5)

# ---------------------------------------------------------------------------
# Button callbacks
# ---------------------------------------------------------------------------

func _on_retry_pressed() -> void:
	_reset_visuals()
	GameManager.start_new_run()


func _on_menu_pressed() -> void:
	_reset_visuals()
	get_tree().paused = false
	SceneManager.change_scene(MAIN_MENU_PATH)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _reset_visuals() -> void:
	overlay.color = Color(0.0, 0.0, 0.0, 0.0)
	content.modulate = Color(1.0, 1.0, 1.0, 0.0)
	overlay.visible = false
	content.visible = false
