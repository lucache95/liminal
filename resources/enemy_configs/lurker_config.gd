class_name LurkerConfig
extends Resource
## Configuration resource for Lurker monster AI parameters.
## The Lurker is an invisible zone-based threat with environmental disturbance.

# Movement
@export var roam_speed: float = 2.0  ## Slow drift speed (player walk is ~4.0)
@export var roam_wait_min: float = 5.0  ## Min pause at roam target
@export var roam_wait_max: float = 12.0  ## Max pause at roam target
@export var roam_range: float = 80.0  ## How far from map center it roams

# Danger zone
@export var danger_zone_radius: float = 15.0  ## Area3D sphere radius
@export var attack_delay: float = 12.0  ## Seconds in zone before kill

# Environmental disturbance
@export var disturbance_radius: float = 20.0  ## Radius for light flicker effects
@export var sanity_drain_multiplier: float = 3.0  ## Multiplied against base drain when in zone
