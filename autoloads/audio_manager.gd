class_name AudioManager
extends Node
## Manages audio bus volumes and an ambient layer system with crossfade support.

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const BUS_NAMES: PackedStringArray = PackedStringArray([
	"Master", "Music", "SFX", "Ambience", "Voice",
])

const LAYER_NAMES: PackedStringArray = PackedStringArray([
	"base_layer", "weather_layer", "location_layer", "tension_layer",
])

const MIN_DB: float = -80.0

# ---------------------------------------------------------------------------
# Bus index cache
# ---------------------------------------------------------------------------

var _bus_indices: Dictionary = {} # String -> int

# ---------------------------------------------------------------------------
# Layer nodes
# ---------------------------------------------------------------------------

var base_layer: AudioStreamPlayer
var weather_layer: AudioStreamPlayer
var location_layer: AudioStreamPlayer
var tension_layer: AudioStreamPlayer
var stinger_player: AudioStreamPlayer

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	_cache_bus_indices()
	_create_layer_nodes()
	EventBus.tension_changed.connect(_on_tension_changed)


func _cache_bus_indices() -> void:
	for bus_name: String in BUS_NAMES:
		var idx: int = AudioServer.get_bus_index(bus_name)
		if idx == -1:
			push_error("AudioManager: bus '%s' not found in AudioServer." % bus_name)
		_bus_indices[bus_name] = idx


func _create_layer_nodes() -> void:
	# Build the five AudioStreamPlayer children programmatically so the
	# autoload scene doesn't need a .tscn wrapper.

	base_layer = _make_layer_player("BaseLayer", "Ambience")
	weather_layer = _make_layer_player("WeatherLayer", "Ambience")
	location_layer = _make_layer_player("LocationLayer", "Ambience")
	tension_layer = _make_layer_player("TensionLayer", "SFX")
	stinger_player = _make_layer_player("StingerPlayer", "SFX")


func _make_layer_player(node_name: String, bus: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = node_name
	player.bus = &bus
	player.volume_db = MIN_DB
	add_child(player)
	return player

# ---------------------------------------------------------------------------
# Bus volume helpers
# ---------------------------------------------------------------------------

## Set bus volume using a linear 0.0–1.0 scale.
func set_bus_volume(bus_name: String, linear: float) -> void:
	var idx: int = _bus_indices.get(bus_name, -1)
	if idx == -1:
		push_error("AudioManager: unknown bus '%s'." % bus_name)
		return
	var db: float = linear_to_db(clampf(linear, 0.0, 1.0))
	AudioServer.set_bus_volume_db(idx, db)


## Return the current bus volume in linear 0.0–1.0 scale.
func get_bus_volume(bus_name: String) -> float:
	var idx: int = _bus_indices.get(bus_name, -1)
	if idx == -1:
		push_error("AudioManager: unknown bus '%s'." % bus_name)
		return 0.0
	return db_to_linear(AudioServer.get_bus_volume_db(idx))

# ---------------------------------------------------------------------------
# Ambient layer system
# ---------------------------------------------------------------------------

## Crossfade a named layer to a new stream over [param duration] seconds.
## Pass [code]null[/code] as [param stream] to fade out only.
func crossfade_layer(layer_name: String, stream: AudioStream, duration: float = 2.0) -> void:
	var player: AudioStreamPlayer = _get_layer_player(layer_name)
	if player == null:
		return

	var tween: Tween = create_tween()
	var half: float = duration * 0.5

	# Fade out current stream
	tween.tween_property(player, "volume_db", MIN_DB, half)
	tween.tween_callback(_swap_stream.bind(player, stream))
	# Fade in new stream (only if a stream was provided)
	if stream != null:
		tween.tween_property(player, "volume_db", 0.0, half)


## Adjust the tension layer volume based on a normalized 0.0–1.0 value.
func set_tension(value: float) -> void:
	var clamped: float = clampf(value, 0.0, 1.0)
	if tension_layer.stream == null:
		return
	if not tension_layer.playing and clamped > 0.0:
		tension_layer.play()

	var target_db: float = lerpf(MIN_DB, 0.0, clamped)
	var tween: Tween = create_tween()
	tween.tween_property(tension_layer, "volume_db", target_db, 0.3)


## Play a one-shot scary stinger sound.
func play_stinger(stream: AudioStream) -> void:
	if stream == null:
		push_error("AudioManager: attempted to play a null stinger stream.")
		return
	stinger_player.stream = stream
	stinger_player.volume_db = 0.0
	stinger_player.play()

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

func _get_layer_player(layer_name: String) -> AudioStreamPlayer:
	match layer_name:
		"base_layer":
			return base_layer
		"weather_layer":
			return weather_layer
		"location_layer":
			return location_layer
		"tension_layer":
			return tension_layer
		_:
			push_error("AudioManager: unknown layer '%s'." % layer_name)
			return null


func _swap_stream(player: AudioStreamPlayer, stream: AudioStream) -> void:
	player.stop()
	player.stream = stream
	if stream != null:
		player.play()

# ---------------------------------------------------------------------------
# Signal callbacks
# ---------------------------------------------------------------------------

func _on_tension_changed(value: float) -> void:
	set_tension(value)
