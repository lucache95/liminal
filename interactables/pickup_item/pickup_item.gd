class_name PickupItem
extends Interactable
## A collectible item that bobs and rotates. Picked up on interact.

# ---------------------------------------------------------------------------
# Exports
# ---------------------------------------------------------------------------

@export var item_id: String = ""
@export var item_name: String = "Item"
@export var bob_amplitude: float = 0.1
@export var rotation_speed: float = 1.0

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const PICKUP_SOUND_INTENSITY: float = 0.2

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var _base_y: float = 0.0
var _time: float = 0.0

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	super._ready()
	one_shot = true
	interaction_prompt = "[E] Pick up " + item_name
	_base_y = position.y


func _process(delta: float) -> void:
	_time += delta
	# Gentle floating bob
	position.y = _base_y + sin(_time * 2.0) * bob_amplitude
	# Slow Y-axis rotation
	rotation_degrees.y += rotation_speed * delta * 60.0

# ---------------------------------------------------------------------------
# Interaction
# ---------------------------------------------------------------------------

func _on_interact(_player: CharacterBody3D) -> void:
	EventBus.item_picked_up.emit(item_id)
	EventBus.sound_emitted.emit(global_position, PICKUP_SOUND_INTENSITY, "pickup")
	queue_free()
