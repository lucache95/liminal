class_name ProximityAudioController
extends Node
## Drives dual-layer proximity audio (heartbeat + drone) based on monster distance.
## Smooth continuous fade -- no stepped thresholds per user design.

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const MIN_DISTANCE: float = 5.0    ## Full intensity when this close
const MAX_DISTANCE: float = 50.0   ## Zero intensity beyond this
const VOLUME_LERP_SPEED: float = 3.0  ## Smoothing speed (higher = snappier)
const HEARTBEAT_MAX_DB: float = -6.0
const HEARTBEAT_MIN_DB: float = -80.0
const DRONE_MAX_DB: float = -12.0
const DRONE_MIN_DB: float = -80.0
const MONSTER_CHECK_INTERVAL: float = 0.5  ## Re-query monster group interval

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var _monster: Node3D = null
var _check_timer: float = 0.0
var _initialized: bool = false

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	# Defer setup to ensure AudioManager is ready
	call_deferred("_deferred_setup")


func _deferred_setup() -> void:
	AudioManager.setup_proximity_audio()
	_initialized = true


func _process(delta: float) -> void:
	if not _initialized:
		return

	# Periodically re-query for monster (avoid doing it every frame)
	_check_timer += delta
	if _check_timer >= MONSTER_CHECK_INTERVAL:
		_check_timer = 0.0
		_monster = get_tree().get_first_node_in_group(&"monster")

	if _monster == null or not is_instance_valid(_monster):
		_fade_out(delta)
		return

	var player: Node3D = get_parent() as Node3D
	if player == null:
		return

	var distance: float = player.global_position.distance_to(_monster.global_position)
	var intensity: float = 1.0 - clampf((distance - MIN_DISTANCE) / (MAX_DISTANCE - MIN_DISTANCE), 0.0, 1.0)

	# Smooth volume transition -- per user: continuous, no steps
	var target_hb_db: float = lerpf(HEARTBEAT_MIN_DB, HEARTBEAT_MAX_DB, intensity)
	AudioManager.heartbeat_layer.volume_db = lerpf(
		AudioManager.heartbeat_layer.volume_db, target_hb_db, VOLUME_LERP_SPEED * delta
	)

	var target_drone_db: float = lerpf(DRONE_MIN_DB, DRONE_MAX_DB, intensity)
	AudioManager.drone_layer.volume_db = lerpf(
		AudioManager.drone_layer.volume_db, target_drone_db, VOLUME_LERP_SPEED * delta
	)


func _fade_out(delta: float) -> void:
	if AudioManager.heartbeat_layer.volume_db > HEARTBEAT_MIN_DB + 1.0:
		AudioManager.heartbeat_layer.volume_db = lerpf(
			AudioManager.heartbeat_layer.volume_db, HEARTBEAT_MIN_DB, VOLUME_LERP_SPEED * delta
		)
	if AudioManager.drone_layer.volume_db > DRONE_MIN_DB + 1.0:
		AudioManager.drone_layer.volume_db = lerpf(
			AudioManager.drone_layer.volume_db, DRONE_MIN_DB, VOLUME_LERP_SPEED * delta
		)
