class_name LurkerAudio
extends Node
## Environmental audio warping when the player is in the Lurker's danger zone.
## Creates a low-frequency drone that intensifies with zone_timer progress.
## Volume ramps from -40dB to -6dB and pitch from 0.8x to 1.5x.

var _audio_player: AudioStreamPlayer3D
var _is_active: bool = false
var _intensity: float = 0.0


func _ready() -> void:
	_audio_player = AudioStreamPlayer3D.new()
	_audio_player.bus = &"Ambience"
	_audio_player.max_distance = 30.0
	_audio_player.volume_db = -80.0
	_audio_player.name = "LurkerDrone"
	get_parent().add_child.call_deferred(_audio_player)

	# Load drone audio -- horror_drone_01.mp3 exists in assets
	var drone_path: String = "res://assets/audio/sfx/horror_drone_01.mp3"
	if ResourceLoader.exists(drone_path):
		var stream: AudioStream = load(drone_path)
		_audio_player.stream = stream

	EventBus.lurker_zone_entered.connect(_on_zone_entered)
	EventBus.lurker_zone_exited.connect(_on_zone_exited)


func _on_zone_entered() -> void:
	_is_active = true
	if _audio_player.stream and not _audio_player.playing:
		_audio_player.play()


func _on_zone_exited() -> void:
	_is_active = false


func _process(delta: float) -> void:
	if not is_instance_valid(_audio_player):
		return

	if _is_active:
		var lurker: Lurker = get_parent() as Lurker
		if lurker and lurker.config:
			_intensity = clampf(lurker._zone_timer / lurker.config.attack_delay, 0.0, 1.0)
		# Ramp volume: louder as danger increases
		_audio_player.volume_db = lerpf(-40.0, -6.0, _intensity)
		# Pitch distortion: rising pitch creates unease
		_audio_player.pitch_scale = lerpf(0.8, 1.5, _intensity)
	else:
		# Fade out gracefully
		_audio_player.volume_db = lerpf(_audio_player.volume_db, -80.0, 3.0 * delta)
		if _audio_player.volume_db < -70.0:
			_audio_player.stop()
