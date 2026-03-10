class_name Interactable
extends StaticBody3D
## Base class for all interactable objects in the world.
## Subclasses override _on_interact() to implement specific behavior.

# ---------------------------------------------------------------------------
# Exports
# ---------------------------------------------------------------------------

@export var interaction_prompt: String = "[E] Interact"
@export var one_shot: bool = false ## Can only be interacted with once.

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var _has_interacted: bool = false

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	add_to_group(&"interactable")


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func get_interaction_prompt() -> String:
	if one_shot and _has_interacted:
		return ""
	return interaction_prompt


func interact(player: CharacterBody3D) -> void:
	if one_shot and _has_interacted:
		return
	_has_interacted = true
	_on_interact(player)


# ---------------------------------------------------------------------------
# Virtual — Override in subclasses
# ---------------------------------------------------------------------------

func _on_interact(_player: CharacterBody3D) -> void:
	pass
