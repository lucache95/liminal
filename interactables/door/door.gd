class_name Door
extends Interactable
## A door that can be opened/closed via tween rotation. Optionally locked.

# ---------------------------------------------------------------------------
# Exports
# ---------------------------------------------------------------------------

@export var is_locked: bool = false
@export var required_key_id: String = ""
@export var is_open: bool = false
@export var open_angle: float = 110.0

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const TWEEN_DURATION: float = 0.8
const SOUND_INTENSITY: float = 0.6

# ---------------------------------------------------------------------------
# Onready
# ---------------------------------------------------------------------------

@onready var _audio_player: AudioStreamPlayer3D = $AudioPlayer

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var _tween: Tween
var _closed_rotation_y: float = 0.0

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	super._ready()
	one_shot = false
	_closed_rotation_y = rotation_degrees.y
	_update_prompt()


# ---------------------------------------------------------------------------
# Interaction
# ---------------------------------------------------------------------------

func _on_interact(_player: CharacterBody3D) -> void:
	if is_locked:
		if required_key_id != "" and _player_has_key(_player):
			is_locked = false
			# Key consumed — unlock and open in one action
			_toggle_door()
		else:
			_play_locked_sound()
			_update_prompt()
		return

	_toggle_door()


# ---------------------------------------------------------------------------
# Door logic
# ---------------------------------------------------------------------------

func _toggle_door() -> void:
	if _tween and _tween.is_running():
		return

	is_open = not is_open

	var target_y: float = _closed_rotation_y + open_angle if is_open else _closed_rotation_y

	_tween = create_tween().set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	_tween.tween_property(self, "rotation_degrees:y", target_y, TWEEN_DURATION)

	_play_door_sound()
	EventBus.sound_emitted.emit(global_position, SOUND_INTENSITY, "door")
	_update_prompt()


func _play_door_sound() -> void:
	if _audio_player and _audio_player.stream:
		_audio_player.play()


func _play_locked_sound() -> void:
	# Reuses the same audio player — swap stream if desired
	if _audio_player and _audio_player.stream:
		_audio_player.play()


func _player_has_key(_player: CharacterBody3D) -> bool:
	if required_key_id == "":
		return false
	# Check if the player has collected the required key via ObjectiveManager
	if ObjectiveManager and ObjectiveManager.completed_ids.has(required_key_id):
		return true
	return false


func _update_prompt() -> void:
	if is_locked:
		interaction_prompt = "[E] Locked"
	elif is_open:
		interaction_prompt = "[E] Close"
	else:
		interaction_prompt = "[E] Open"
