class_name StateMachine
extends Node
## Generic reusable finite state machine.
## Add State nodes as children. Set initial_state in the inspector.

@export var initial_state: State

var current_state: State
var states: Dictionary = {} # String -> State


func _ready() -> void:
	for child: Node in get_children():
		if child is State:
			states[child.name.to_lower()] = child
			child.state_machine = self
	if initial_state:
		current_state = initial_state
		current_state.enter({})


func _physics_process(delta: float) -> void:
	if current_state:
		current_state.physics_update(delta)


func _process(delta: float) -> void:
	if current_state:
		current_state.frame_update(delta)


func transition_to(target_state_name: String, data: Dictionary = {}) -> void:
	var new_state: State = states.get(target_state_name.to_lower())
	if new_state == null:
		push_error("StateMachine: State not found: " + target_state_name)
		return
	if new_state == current_state:
		return
	if current_state:
		current_state.exit()
	current_state = new_state
	current_state.enter(data)
	EventBus.emit_signal("monster_state_changed", target_state_name)
