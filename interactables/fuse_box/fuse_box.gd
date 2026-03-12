class_name FuseBox
extends Interactable
## A wall-mounted fuse box that powers up when a fuse is inserted.
## Moderate sound on activation — less risky than generators.

# ---------------------------------------------------------------------------
# Exports
# ---------------------------------------------------------------------------

@export var fuse_box_id: String = ""
@export var is_activated: bool = false

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const ACTIVATION_SOUND_INTENSITY: float = 0.6
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
	interaction_prompt = "[E] Insert Fuse"
	if _indicator_light:
		_indicator_light.light_energy = 0.0

# ---------------------------------------------------------------------------
# Interaction
# ---------------------------------------------------------------------------

func _on_interact(_player: CharacterBody3D) -> void:
	if is_activated:
		return

	is_activated = true
	interaction_prompt = ""

	# Play activation sound
	if _audio_player and _audio_player.stream:
		_audio_player.play()

	# Moderate sound — less risky than a generator
	EventBus.emit_signal("sound_emitted", global_position, ACTIVATION_SOUND_INTENSITY, "fuse_box")

	# Mark objective as completed
	EventBus.emit_signal("objective_completed", fuse_box_id)

	# Flicker the indicator light on
	_flicker_light_on()


func _flicker_light_on() -> void:
	if not _indicator_light:
		return

	var tween: Tween = create_tween()
	for i: int in range(FLICKER_COUNT):
		tween.tween_property(_indicator_light, "light_energy", 2.0, FLICKER_INTERVAL)
		tween.tween_property(_indicator_light, "light_energy", 0.0, FLICKER_INTERVAL)
	tween.tween_property(_indicator_light, "light_energy", 2.0, LIGHT_TWEEN_DURATION)
