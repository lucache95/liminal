class_name Generator
extends Interactable
## An activatable generator that powers up when interacted with.
## Emits a loud sound on activation, alerting the monster.

# ---------------------------------------------------------------------------
# Exports
# ---------------------------------------------------------------------------

@export var generator_id: String = ""
@export var is_powered: bool = false

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const ACTIVATION_SOUND_INTENSITY: float = 0.8
const LIGHT_TWEEN_DURATION: float = 0.5
const FLICKER_INTERVAL: float = 0.15
const FLICKER_COUNT: int = 4

# ---------------------------------------------------------------------------
# Onready
# ---------------------------------------------------------------------------

@onready var _indicator_light: OmniLight3D = $IndicatorLight
@onready var _audio_player: AudioStreamPlayer3D = $AudioPlayer

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	super._ready()
	one_shot = true
	interaction_prompt = "[E] Activate Generator"
	# Ensure light starts off
	if _indicator_light:
		_indicator_light.light_energy = 0.0

# ---------------------------------------------------------------------------
# Interaction
# ---------------------------------------------------------------------------

func _on_interact(_player: CharacterBody3D) -> void:
	if is_powered:
		return

	is_powered = true
	interaction_prompt = ""

	# Play activation sound
	if _audio_player and _audio_player.stream:
		_audio_player.play()

	# Loud sound — alerts the monster
	EventBus.sound_emitted.emit(global_position, ACTIVATION_SOUND_INTENSITY, "generator")

	# Mark objective as completed
	EventBus.objective_completed.emit(generator_id)

	# Flicker the indicator light on for dramatic effect
	_flicker_light_on()


func _flicker_light_on() -> void:
	if not _indicator_light:
		return

	var tween: Tween = create_tween()
	# Flicker rapidly before settling
	for i: int in range(FLICKER_COUNT):
		tween.tween_property(_indicator_light, "light_energy", 2.0, FLICKER_INTERVAL)
		tween.tween_property(_indicator_light, "light_energy", 0.0, FLICKER_INTERVAL)
	# Settle to final energy
	tween.tween_property(_indicator_light, "light_energy", 2.0, LIGHT_TWEEN_DURATION)
