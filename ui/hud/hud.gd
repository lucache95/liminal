class_name HUD
extends CanvasLayer
## Minimal in-game heads-up display: crosshair, interaction prompt,
## flashlight battery indicator, and screen flash effects.

# ---------------------------------------------------------------------------
# @onready references
# ---------------------------------------------------------------------------

@onready var interaction_prompt: Label = %InteractionPrompt
@onready var flashlight_indicator: ProgressBar = %FlashlightIndicator
@onready var screen_flash: ColorRect = %ScreenFlash

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var _flash_tween: Tween

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	interaction_prompt.visible = false
	flashlight_indicator.visible = false
	screen_flash.color = Color(1.0, 1.0, 1.0, 0.0)

	EventBus.connect("interaction_prompt_show", _on_interaction_prompt_show)
	EventBus.connect("interaction_prompt_hide", _on_interaction_prompt_hide)
	EventBus.connect("flashlight_toggled", _on_flashlight_toggled)
	EventBus.connect("battery_changed", update_battery)
	EventBus.connect("player_died", _on_player_died)

# ---------------------------------------------------------------------------
# Interaction prompt
# ---------------------------------------------------------------------------

func _on_interaction_prompt_show(text: String) -> void:
	interaction_prompt.text = text
	interaction_prompt.visible = true


func _on_interaction_prompt_hide() -> void:
	interaction_prompt.visible = false

# ---------------------------------------------------------------------------
# Flashlight battery
# ---------------------------------------------------------------------------

func _on_flashlight_toggled(is_on: bool) -> void:
	flashlight_indicator.visible = is_on


## Update the battery indicator percentage (0.0 to 100.0) with color coding.
func update_battery(percent: float) -> void:
	flashlight_indicator.value = clampf(percent, 0.0, 100.0)

	# Color-code the bar: green > 50%, yellow 20-50%, red < 20%
	if percent > 50.0:
		flashlight_indicator.modulate = Color(0.3, 0.8, 0.3)
	elif percent > 20.0:
		flashlight_indicator.modulate = Color(0.9, 0.8, 0.2)
	else:
		flashlight_indicator.modulate = Color(0.9, 0.2, 0.2)

# ---------------------------------------------------------------------------
# Screen flash
# ---------------------------------------------------------------------------

## Flash the screen with [param color] then fade out over [param duration].
func flash_screen(color: Color, duration: float = 0.3) -> void:
	if _flash_tween and _flash_tween.is_running():
		_flash_tween.kill()

	screen_flash.color = Color(color.r, color.g, color.b, 0.5)
	_flash_tween = create_tween()
	_flash_tween.tween_property(screen_flash, "color:a", 0.0, duration)


func _on_player_died() -> void:
	flash_screen(Color.RED, 0.6)
