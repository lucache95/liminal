extends CanvasLayer
## Debug overlay for atmosphere system validation.
## Displays real-time sanity, weather, day/night progress, and light degradation.
## F9 toggles overlay. Ctrl+1/2/3 force sanity tiers for testing. Ctrl+0 resets.

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var _label: Label
var _sanity: float = 1.0
var _day_night_t: float = 0.0
var _weather: String = "unknown"
var _lights_degraded: int = 0
var _debug_override: bool = false
var _visible: bool = false

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	layer = 100

	_label = Label.new()
	_label.position = Vector2(10, 10)
	_label.add_theme_font_size_override(&"font_size", 14)
	_label.add_theme_color_override(&"font_color", Color.YELLOW)
	_label.visible = false
	add_child(_label)

	# Connect signals -- guarded because these may not exist yet (added by Plans 01-04).
	if EventBus:
		if EventBus.has_signal(&"sanity_changed"):
			EventBus.sanity_changed.connect(func(v: float) -> void: _sanity = v)
		if EventBus.has_signal(&"day_night_progress"):
			EventBus.day_night_progress.connect(func(t: float) -> void: _day_night_t = t)
		if EventBus.has_signal(&"weather_set"):
			EventBus.weather_set.connect(func(w: String) -> void: _weather = w)
		if EventBus.has_signal(&"light_degraded"):
			EventBus.light_degraded.connect(func(_p: NodePath) -> void: _lights_degraded += 1)

# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	# Toggle debug overlay with F9
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F9:
			_visible = !_visible
			_label.visible = _visible
			get_viewport().set_input_as_handled()
			return

	# Debug sanity overrides (only when overlay is visible)
	if not _visible:
		return

	if event is InputEventKey and event.pressed and not event.echo and event.ctrl_pressed:
		match event.keycode:
			KEY_1:
				_debug_override = true
				_sanity = 0.7
				if EventBus and EventBus.has_signal(&"sanity_changed"):
					EventBus.sanity_changed.emit(0.7)
				get_viewport().set_input_as_handled()
			KEY_2:
				_debug_override = true
				_sanity = 0.4
				if EventBus and EventBus.has_signal(&"sanity_changed"):
					EventBus.sanity_changed.emit(0.4)
				get_viewport().set_input_as_handled()
			KEY_3:
				_debug_override = true
				_sanity = 0.1
				if EventBus and EventBus.has_signal(&"sanity_changed"):
					EventBus.sanity_changed.emit(0.1)
				get_viewport().set_input_as_handled()
			KEY_0:
				_debug_override = false
				_sanity = 1.0
				if EventBus and EventBus.has_signal(&"sanity_changed"):
					EventBus.sanity_changed.emit(1.0)
				get_viewport().set_input_as_handled()

# ---------------------------------------------------------------------------
# HUD update
# ---------------------------------------------------------------------------

func _process(_delta: float) -> void:
	if not _visible:
		return

	var text: String = "[ATMOSPHERE DEBUG]\n"
	text += "Sanity: %.2f %s\n" % [_sanity, "(OVERRIDE)" if _debug_override else ""]
	text += "Day/Night: %.2f (%.0f%%)\n" % [_day_night_t, _day_night_t * 100.0]
	text += "Weather: %s\n" % _weather
	text += "Lights degraded: %d\n" % _lights_degraded
	text += "\n[Keys]\n"
	text += "F9: Toggle overlay\n"
	text += "Ctrl+1: Sanity 0.7 (mild)\n"
	text += "Ctrl+2: Sanity 0.4 (medium)\n"
	text += "Ctrl+3: Sanity 0.1 (severe)\n"
	text += "Ctrl+0: Reset sanity\n"
	_label.text = text
