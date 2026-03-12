class_name KillZone
extends Area3D
## Invisible instant-death zone for Ambusher monster type. Placed by seed-deterministic
## spawner. Kills on player entry with a brief horrifying distortion flash.


func _ready() -> void:
	collision_layer = 16  # Layer 5: Triggers
	collision_mask = 2    # Layer 2: Player
	monitoring = true
	monitorable = false
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group(&"player"):
		return

	# Brief horrifying distortion flash before death
	var post_process: Node = get_tree().get_first_node_in_group(&"post_process")
	if post_process and post_process.has_method(&"set_death_intensity"):
		post_process.set_death_intensity(0.8)  # Strong flash
		var flash_tween: Tween = create_tween()
		flash_tween.tween_interval(0.15)
		flash_tween.tween_callback(func() -> void: EventBus.player_died.emit())
	else:
		EventBus.player_died.emit()
