class_name ObjectiveTemplate
extends Resource
## Defines a single objective type that can be selected for a run.

# ---------------------------------------------------------------------------
# Enums
# ---------------------------------------------------------------------------

enum ObjectiveType { FIND_ITEMS, ACTIVATE_GENERATORS, SOLVE_SEQUENCE, REACH_LOCATION }

# ---------------------------------------------------------------------------
# Exports
# ---------------------------------------------------------------------------

@export var objective_id: String = ""
@export var type: ObjectiveType = ObjectiveType.FIND_ITEMS
@export var display_hint: String = "" ## Vague environmental clue text shown to player.
@export var required_count: int = 3 ## How many items/generators/etc. needed to complete.
@export var item_scene: PackedScene ## Scene to spawn for collectible objectives.
@export var difficulty_weight: float = 1.0 ## Higher = harder, affects selection weighting.
