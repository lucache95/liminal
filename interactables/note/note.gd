class_name Note
extends Interactable
## A readable note or lore item. Can be re-read multiple times.

# ---------------------------------------------------------------------------
# Exports
# ---------------------------------------------------------------------------

@export var note_title: String = ""
@export_multiline var note_text: String = ""
@export var note_id: String = ""

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	super._ready()
	one_shot = false
	interaction_prompt = "[E] Read"

# ---------------------------------------------------------------------------
# Interaction
# ---------------------------------------------------------------------------

func _on_interact(_player: CharacterBody3D) -> void:
	# Emit as a collected clue so ObjectiveManager can track it
	if note_id != "":
		EventBus.emit_signal("item_picked_up", note_id)

	# TODO: Replace with proper note UI overlay when implemented
	print("[Note] %s: %s" % [note_title, note_text])
