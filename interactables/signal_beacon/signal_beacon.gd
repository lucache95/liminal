class_name SignalBeacon
extends Interactable
## A tall signal beacon that sends an emergency signal when activated.
## Very loud — high risk, high reward. Dramatic flash on activation.

# ---------------------------------------------------------------------------
# Exports
# ---------------------------------------------------------------------------

@export var beacon_id: String = ""
@export var is_active: bool = false

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const ACTIVATION_SOUND_INTENSITY: float = 0.9
const FLASH_PEAK_ENERGY: float = 5.0
const SETTLE_ENERGY: float = 2.0
const FLASH_UP_DURATION: float = 0.2
const FLASH_DOWN_DURATION: float = 0.5

# ---------------------------------------------------------------------------
# Onready
# ---------------------------------------------------------------------------

@onready var _beacon_light: OmniLight3D = $BeaconLight
@onready var _audio_player: AudioStreamPlayer3D = $AudioPlayer

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	super._ready()
	one_shot = true
	interaction_prompt = "[E] Activate Beacon"
	if _beacon_light:
		_beacon_light.light_energy = 0.0

# ---------------------------------------------------------------------------
# Interaction
# ---------------------------------------------------------------------------

func _on_interact(_player: CharacterBody3D) -> void:
	if is_active:
		return

	is_active = true
	interaction_prompt = ""

	# Play activation sound
	if _audio_player and _audio_player.stream:
		_audio_player.play()

	# Very loud — high risk
	EventBus.emit_signal("sound_emitted", global_position, ACTIVATION_SOUND_INTENSITY, "signal_beacon")

	# Mark objective as completed
	EventBus.emit_signal("objective_completed", beacon_id)

	# Dramatic activation flash then steady pulse
	_flash_beacon()


func _flash_beacon() -> void:
	if not _beacon_light:
		return

	var tween: Tween = create_tween()
	# Bright flash up
	tween.tween_property(_beacon_light, "light_energy", FLASH_PEAK_ENERGY, FLASH_UP_DURATION)
	# Settle to steady glow
	tween.tween_property(_beacon_light, "light_energy", SETTLE_ENERGY, FLASH_DOWN_DURATION)
