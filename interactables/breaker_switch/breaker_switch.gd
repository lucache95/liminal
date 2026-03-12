class_name BreakerSwitch
extends Interactable
## A wall-mounted breaker switch that restores a circuit when flipped.
## Quiet activation — a stealthier alternative to generators.

# ---------------------------------------------------------------------------
# Exports
# ---------------------------------------------------------------------------

@export var switch_id: String = ""
@export var is_flipped: bool = false

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const ACTIVATION_SOUND_INTENSITY: float = 0.3
const LIGHT_TWEEN_DURATION: float = 0.4

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
	interaction_prompt = "[E] Flip Switch"
	if _indicator_light:
		_indicator_light.light_energy = 0.0

# ---------------------------------------------------------------------------
# Interaction
# ---------------------------------------------------------------------------

func _on_interact(_player: CharacterBody3D) -> void:
	if is_flipped:
		return

	is_flipped = true
	interaction_prompt = ""

	# Play activation sound
	if _audio_player and _audio_player.stream:
		_audio_player.play()

	# Quiet sound — stealthy option
	EventBus.emit_signal("sound_emitted", global_position, ACTIVATION_SOUND_INTENSITY, "breaker_switch")

	# Mark objective as completed
	EventBus.emit_signal("objective_completed", switch_id)

	# Clean tween to indicator light — no flicker, just a smooth turn-on
	_turn_light_on()


func _turn_light_on() -> void:
	if not _indicator_light:
		return

	var tween: Tween = create_tween()
	tween.tween_property(_indicator_light, "light_energy", 1.5, LIGHT_TWEEN_DURATION)
