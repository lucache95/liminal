class_name StalkerAudio
extends Node
## Manages all audio for the stalker monster: breathing, growling, footsteps, and state transitions.

const FOOTSTEP_INTERVAL_PATROL: float = 0.8
const FOOTSTEP_INTERVAL_CHASE: float = 0.4
const BREATHING_INTERVAL: float = 4.0

var _breathing_sounds: Array[AudioStream] = []
var _growl_sounds: Array[AudioStream] = []
var _footstep_sounds: Array[AudioStream] = []

var _footstep_timer: float = 0.0
var _breathing_timer: float = 0.0
var _current_state: String = ""

@onready var _stalker: CharacterBody3D = get_parent()
@onready var _audio_player: AudioStreamPlayer3D = _stalker.get_node("AudioPlayer")

# Secondary audio player for layered sounds (breathing while footsteps play).
var _breathing_player: AudioStreamPlayer3D


func _ready() -> void:
	_load_sounds()
	_create_breathing_player()
	EventBus.connect("monster_state_changed", _on_state_changed)


func _physics_process(delta: float) -> void:
	var speed: float = _stalker.blackboard.get("current_speed", 0.0)

	# Footsteps when moving
	if speed > 0.5:
		var interval: float = FOOTSTEP_INTERVAL_CHASE if _current_state == "chasestate" else FOOTSTEP_INTERVAL_PATROL
		_footstep_timer += delta
		if _footstep_timer >= interval:
			_footstep_timer = 0.0
			_play_random(_audio_player, _footstep_sounds, 0.85, 1.15)
			# Emit sound for player hearing system
			EventBus.emit_signal("sound_emitted", _stalker.global_position, 0.6, "monster_footstep")

	# Ambient breathing
	_breathing_timer += delta
	if _breathing_timer >= BREATHING_INTERVAL:
		_breathing_timer = 0.0
		if _current_state in ["patrolstate", "idlestate", "searchstate"]:
			_play_random(_breathing_player, _breathing_sounds, 0.9, 1.1)


func _on_state_changed(new_state: String) -> void:
	_current_state = new_state.to_lower()

	# Play growl when entering chase or investigate
	if _current_state in ["chasestate", "investigatestate"]:
		_play_random(_audio_player, _growl_sounds, 0.8, 1.2)


func _load_sounds() -> void:
	var breathing_paths: Array[String] = [
		"res://assets/audio/sfx/monster_breathing_01.mp3",
		"res://assets/audio/sfx/monster_breathing_02.mp3",
	]
	var growl_paths: Array[String] = [
		"res://assets/audio/sfx/monster_growl_01.mp3",
		"res://assets/audio/sfx/monster_growl_02.mp3",
	]
	var footstep_paths: Array[String] = [
		"res://assets/audio/sfx/monster_footstep_heavy_01.mp3",
		"res://assets/audio/sfx/monster_footstep_heavy_02.mp3",
		"res://assets/audio/sfx/monster_footstep_heavy_03.mp3",
	]

	_breathing_sounds = _try_load(breathing_paths)
	_growl_sounds = _try_load(growl_paths)
	_footstep_sounds = _try_load(footstep_paths)


func _create_breathing_player() -> void:
	_breathing_player = AudioStreamPlayer3D.new()
	_breathing_player.name = "BreathingPlayer"
	_breathing_player.bus = &"SFX"
	_breathing_player.max_distance = 25.0
	_breathing_player.volume_db = -6.0
	_stalker.add_child(_breathing_player)


func _try_load(paths: Array[String]) -> Array[AudioStream]:
	var streams: Array[AudioStream] = []
	for path: String in paths:
		if ResourceLoader.exists(path):
			var stream: AudioStream = load(path) as AudioStream
			if stream:
				streams.append(stream)
	return streams


func _play_random(player: AudioStreamPlayer3D, sounds: Array[AudioStream], pitch_min: float, pitch_max: float) -> void:
	if sounds.is_empty() or player == null:
		return
	if player.playing:
		return
	player.stream = sounds[randi() % sounds.size()]
	player.pitch_scale = randf_range(pitch_min, pitch_max)
	player.play()
