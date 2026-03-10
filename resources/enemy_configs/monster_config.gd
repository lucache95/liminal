class_name MonsterConfig
extends Resource
## Configuration resource for monster AI parameters.
## Exported properties are tunable per-monster in the inspector.

@export var display_name: String = "Stalker"

# Movement speeds
@export var patrol_speed: float = 2.5
@export var investigate_speed: float = 3.5
@export var chase_speed: float = 6.0

# Sight detection
@export var sight_range: float = 30.0
@export var sight_angle_degrees: float = 60.0

# Hearing detection
@export var hearing_range: float = 40.0

# Light detection
@export var light_threshold: float = 0.3

# Alert system
@export var alert_buildup_rate: float = 0.2
@export var alert_decay_rate: float = 0.05

# State timing
@export var lose_interest_time: float = 15.0
@export var search_duration: float = 30.0
