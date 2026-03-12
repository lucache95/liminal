class_name EnvironmentalClueManager
extends Node
## Places contextual visual/lighting clues near active objective locations.
## No UI markers -- clues are purely environmental (colored accent lights).
## Clue lights use the "objective_clue" group, NOT "light_source".


# -----------------------------------------------------------------------
# Constants
# -----------------------------------------------------------------------

const CLUE_RADIUS: float = 8.0  ## How far from objective center clues appear
const CLUE_LIGHT_ENERGY: float = 0.15  ## Subtle, not obvious
const CLUE_LIGHT_RANGE: float = 4.0
const BREADCRUMB_SPACING: float = 12.0  ## Spacing for breadcrumb trail lights
const BREADCRUMB_COUNT: int = 2  ## Number of breadcrumb lights per objective

## Color configs keyed by objective_id -- different colors per objective type.
const CLUE_CONFIGS: Dictionary = {
	"generators": { "light_color": Color(0.1, 0.4, 0.9) },        # Blue: electrical
	"key_fragments": { "light_color": Color(0.9, 0.8, 0.2) },     # Amber: metallic
	"fuse_boxes": { "light_color": Color(0.9, 0.5, 0.1) },        # Orange: sparks
	"breaker_switches": { "light_color": Color(0.2, 0.8, 0.2) },  # Green: circuit
	"valve_handles": { "light_color": Color(0.2, 0.5, 0.9) },     # Teal: water
	"signal_beacons": { "light_color": Color(0.9, 0.2, 0.1) },    # Red: signal
	"gate_parts": { "light_color": Color(0.7, 0.7, 0.3) },        # Pale yellow: way out
	"radio_tune": { "light_color": Color(0.5, 0.2, 0.8) },        # Purple: radio waves
}


# -----------------------------------------------------------------------
# Public Methods
# -----------------------------------------------------------------------

func place_clues(template: ObjectiveTemplate, spawn_positions: Array[Vector3], rng: RandomNumberGenerator) -> void:
	## Place environmental clue lights near each active objective spawn position.
	var config: Dictionary = CLUE_CONFIGS.get(template.objective_id, {})
	if config.is_empty():
		return

	for pos: Vector3 in spawn_positions:
		_place_proximity_lights(pos, config, rng)
		_place_breadcrumb_lights(pos, config, rng)


func clear_clues() -> void:
	## Remove and free all clue lights (called on reset).
	for child: Node in get_children():
		child.queue_free()


# -----------------------------------------------------------------------
# Private Methods
# -----------------------------------------------------------------------

func _place_proximity_lights(center: Vector3, config: Dictionary, rng: RandomNumberGenerator) -> void:
	## Place 1-2 subtle OmniLight3D nodes at random offsets within CLUE_RADIUS.
	var count: int = rng.randi_range(1, 2)

	for i: int in range(count):
		var light: OmniLight3D = OmniLight3D.new()
		light.name = "ProxClue_%d" % get_child_count()
		light.light_energy = CLUE_LIGHT_ENERGY
		light.omni_range = CLUE_LIGHT_RANGE
		light.light_color = config["light_color"]

		# Random offset on XZ plane within CLUE_RADIUS
		var angle: float = rng.randf() * TAU
		var dist: float = rng.randf_range(0.3 * CLUE_RADIUS, CLUE_RADIUS)
		var offset_x: float = cos(angle) * dist
		var offset_z: float = sin(angle) * dist

		light.position = Vector3(center.x + offset_x, center.y + 0.5, center.z + offset_z)

		# CRITICAL: Use objective_clue group, NOT light_source
		light.add_to_group(&"objective_clue")
		add_child(light)


func _place_breadcrumb_lights(center: Vector3, config: Dictionary, rng: RandomNumberGenerator) -> void:
	## Place BREADCRUMB_COUNT lights along a random approach direction, leading toward the objective.
	var approach_angle: float = rng.randf() * TAU

	for i: int in range(BREADCRUMB_COUNT):
		var light: OmniLight3D = OmniLight3D.new()
		light.name = "BreadClue_%d" % get_child_count()
		light.light_energy = CLUE_LIGHT_ENERGY * 0.6  # Even more subtle than proximity lights
		light.omni_range = CLUE_LIGHT_RANGE * 0.7
		light.light_color = config["light_color"]

		# Place along approach direction, starting from CLUE_RADIUS * 1.5
		var dist: float = CLUE_RADIUS * 1.5 + (i * BREADCRUMB_SPACING)
		var offset_x: float = cos(approach_angle) * dist
		var offset_z: float = sin(approach_angle) * dist

		light.position = Vector3(center.x + offset_x, center.y + 0.5, center.z + offset_z)

		# CRITICAL: Use objective_clue group, NOT light_source
		light.add_to_group(&"objective_clue")
		add_child(light)
