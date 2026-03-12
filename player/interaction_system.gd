class_name InteractionSystem
extends RayCast3D
## Raycasts forward from the player head to detect and interact with objects.

var _current_target: Node3D = null


func _ready() -> void:
	enabled = true


func _physics_process(_delta: float) -> void:
	if not is_colliding():
		_clear_target()
		return

	var collider: Object = get_collider()
	if collider == null or not collider is Node3D:
		_clear_target()
		return

	var target: Node3D = collider as Node3D

	# Check if the target is interactable
	if target.has_method("get_interaction_prompt"):
		if target != _current_target:
			# New target — show its prompt
			_current_target = target
			var prompt: String = target.get_interaction_prompt()
			EventBus.emit_signal("interaction_prompt_show", prompt)
	else:
		_clear_target()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"interact"):
		_try_interact()


func _try_interact() -> void:
	if _current_target == null:
		return

	if not is_instance_valid(_current_target):
		_clear_target()
		return

	if _current_target.has_method("interact"):
		var player: CharacterBody3D = get_parent().get_parent() as CharacterBody3D
		_current_target.interact(player)


func _clear_target() -> void:
	if _current_target != null:
		_current_target = null
		EventBus.emit_signal("interaction_prompt_hide")
