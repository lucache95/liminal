class_name PlayerFlashlight
extends SpotLight3D
## Player-held flashlight with battery drain and low-battery flicker.

# --- Exports ---
@export var max_battery: float = 100.0
@export var drain_rate: float = 2.0
@export var is_on: bool = false

# --- State ---
var current_battery: float = 100.0

# Flicker
var _flicker_timer: float = 0.0
var _base_energy: float = 1.2
const FLICKER_INTERVAL_MIN: float = 0.05
const FLICKER_INTERVAL_MAX: float = 0.3
const FLICKER_LOW_THRESHOLD: float = 20.0
var _next_flicker_time: float = 0.1


func _ready() -> void:
	current_battery = max_battery
	_base_energy = light_energy
	visible = is_on


func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"flashlight_toggle"):
		toggle()


func _process(delta: float) -> void:
	if not is_on:
		return

	# Drain battery
	current_battery = maxf(current_battery - drain_rate * delta, 0.0)

	# Turn off when empty
	if current_battery <= 0.0:
		toggle()
		return

	# Flicker effect when battery is low
	if get_battery_percent() < FLICKER_LOW_THRESHOLD:
		_update_flicker(delta)
	else:
		light_energy = _base_energy


## Toggle the flashlight on or off.
func toggle() -> void:
	if not is_on and current_battery <= 0.0:
		return  # Can't turn on with no battery

	is_on = not is_on
	visible = is_on

	if is_on:
		light_energy = _base_energy
	else:
		light_energy = _base_energy  # Reset on turn off

	EventBus.flashlight_toggled.emit(is_on)


## Returns battery as a percentage 0.0 - 100.0.
func get_battery_percent() -> float:
	return (current_battery / max_battery) * 100.0


## Recharge the battery by a given amount.
func recharge(amount: float) -> void:
	current_battery = minf(current_battery + amount, max_battery)


func _update_flicker(delta: float) -> void:
	_flicker_timer += delta
	if _flicker_timer >= _next_flicker_time:
		_flicker_timer = 0.0
		_next_flicker_time = randf_range(FLICKER_INTERVAL_MIN, FLICKER_INTERVAL_MAX)

		# Random energy variation — dimmer as battery drops
		var battery_factor: float = get_battery_percent() / FLICKER_LOW_THRESHOLD
		var min_energy: float = _base_energy * 0.2 * battery_factor
		var max_energy: float = _base_energy * 0.9
		light_energy = randf_range(min_energy, max_energy)
