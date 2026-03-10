class_name State
extends Node
## Base state class for the finite state machine.
## Subclass this and override enter/exit/physics_update/frame_update.

var state_machine: StateMachine


func enter(_data: Dictionary) -> void:
	pass


func exit() -> void:
	pass


func physics_update(_delta: float) -> void:
	pass


func frame_update(_delta: float) -> void:
	pass
