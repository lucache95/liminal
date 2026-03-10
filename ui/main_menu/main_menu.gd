class_name MainMenu
extends Control
## Main menu screen with new game, settings, and quit options.

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const SETTINGS_PATH: String = "user://settings.cfg"

# ---------------------------------------------------------------------------
# @onready references
# ---------------------------------------------------------------------------

@onready var new_game_button: Button = %NewGameButton
@onready var settings_button: Button = %SettingsButton
@onready var quit_button: Button = %QuitButton
@onready var settings_panel: PanelContainer = %SettingsPanel
@onready var settings_back_button: Button = %SettingsBackButton
@onready var master_slider: HSlider = %MasterSlider
@onready var sfx_slider: HSlider = %SFXSlider
@onready var music_slider: HSlider = %MusicSlider
@onready var sensitivity_slider: HSlider = %SensitivitySlider
@onready var fullscreen_check: CheckBox = %FullscreenCheck

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	new_game_button.pressed.connect(_on_new_game_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	settings_back_button.pressed.connect(_on_settings_back_pressed)

	master_slider.value_changed.connect(_on_master_volume_changed)
	sfx_slider.value_changed.connect(_on_sfx_volume_changed)
	music_slider.value_changed.connect(_on_music_volume_changed)
	sensitivity_slider.value_changed.connect(_on_sensitivity_changed)
	fullscreen_check.toggled.connect(_on_fullscreen_toggled)

	_load_settings()

# ---------------------------------------------------------------------------
# Button callbacks
# ---------------------------------------------------------------------------

func _on_new_game_pressed() -> void:
	GameManager.start_new_run()


func _on_settings_pressed() -> void:
	settings_panel.visible = true


func _on_quit_pressed() -> void:
	get_tree().quit()


func _on_settings_back_pressed() -> void:
	settings_panel.visible = false
	_save_settings()

# ---------------------------------------------------------------------------
# Settings callbacks
# ---------------------------------------------------------------------------

func _on_master_volume_changed(value: float) -> void:
	AudioManager.set_bus_volume("Master", value / 100.0)


func _on_sfx_volume_changed(value: float) -> void:
	AudioManager.set_bus_volume("SFX", value / 100.0)


func _on_music_volume_changed(value: float) -> void:
	AudioManager.set_bus_volume("Music", value / 100.0)


func _on_sensitivity_changed(_value: float) -> void:
	# Sensitivity is read by the player controller from this config.
	# We just save it here; no immediate AudioManager call needed.
	pass


func _on_fullscreen_toggled(pressed: bool) -> void:
	if pressed:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

# ---------------------------------------------------------------------------
# Settings persistence
# ---------------------------------------------------------------------------

func _save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("audio", "master", master_slider.value)
	config.set_value("audio", "sfx", sfx_slider.value)
	config.set_value("audio", "music", music_slider.value)
	config.set_value("controls", "sensitivity", sensitivity_slider.value)
	config.set_value("video", "fullscreen", fullscreen_check.button_pressed)
	var err: Error = config.save(SETTINGS_PATH)
	if err != OK:
		push_error("MainMenu: failed to save settings (error %d)." % err)


func _load_settings() -> void:
	var config := ConfigFile.new()
	var err: Error = config.load(SETTINGS_PATH)
	if err != OK:
		# No saved settings yet — use defaults and apply them.
		_apply_defaults()
		return

	master_slider.value = config.get_value("audio", "master", 80.0)
	sfx_slider.value = config.get_value("audio", "sfx", 80.0)
	music_slider.value = config.get_value("audio", "music", 80.0)
	sensitivity_slider.value = config.get_value("controls", "sensitivity", 50.0)
	fullscreen_check.button_pressed = config.get_value("video", "fullscreen", false)

	# Apply loaded values to audio buses.
	AudioManager.set_bus_volume("Master", master_slider.value / 100.0)
	AudioManager.set_bus_volume("SFX", sfx_slider.value / 100.0)
	AudioManager.set_bus_volume("Music", music_slider.value / 100.0)


func _apply_defaults() -> void:
	master_slider.value = 80.0
	sfx_slider.value = 80.0
	music_slider.value = 80.0
	sensitivity_slider.value = 50.0
	fullscreen_check.button_pressed = false

	AudioManager.set_bus_volume("Master", 0.8)
	AudioManager.set_bus_volume("SFX", 0.8)
	AudioManager.set_bus_volume("Music", 0.8)
