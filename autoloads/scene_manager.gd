class_name SceneManager
extends Node
## Handles scene transitions with fade-to-black using async resource loading.

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const FADE_COLOR: Color = Color.BLACK

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var _is_transitioning: bool = false

# ---------------------------------------------------------------------------
# Overlay nodes
# ---------------------------------------------------------------------------

var _canvas_layer: CanvasLayer
var _fade_rect: ColorRect

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_overlay()


func _build_overlay() -> void:
	_canvas_layer = CanvasLayer.new()
	_canvas_layer.name = "FadeOverlay"
	# Render above everything else.
	_canvas_layer.layer = 128
	add_child(_canvas_layer)

	_fade_rect = ColorRect.new()
	_fade_rect.name = "FadeRect"
	_fade_rect.color = FADE_COLOR
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Fill the entire viewport.
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Start fully transparent (not visible).
	_fade_rect.modulate.a = 0.0
	_canvas_layer.add_child(_fade_rect)

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Transition to a new scene with a fade-to-black effect.
## [param scene_path] must be a valid [code]res://[/code] path to a
## [code].tscn[/code] or [code].scn[/code] file.
func change_scene(scene_path: String, fade_duration: float = 0.5) -> void:
	if _is_transitioning:
		push_error("SceneManager: transition already in progress, ignoring request for '%s'." % scene_path)
		return

	_is_transitioning = true
	await _fade_out(fade_duration)
	await _load_scene_async(scene_path)
	await _fade_in(fade_duration)
	_is_transitioning = false


## Reload the current scene with a fade transition.
func reload_current_scene(fade_duration: float = 0.5) -> void:
	var current_scene: Node = get_tree().current_scene
	if current_scene == null:
		push_error("SceneManager: no current scene to reload.")
		return
	var scene_path: String = current_scene.scene_file_path
	if scene_path.is_empty():
		push_error("SceneManager: current scene has no file path; cannot reload.")
		return
	change_scene(scene_path, fade_duration)

# ---------------------------------------------------------------------------
# Fade helpers
# ---------------------------------------------------------------------------

func _fade_out(duration: float) -> void:
	var tween: Tween = create_tween()
	tween.tween_property(_fade_rect, "modulate:a", 1.0, duration)
	await tween.finished


func _fade_in(duration: float) -> void:
	var tween: Tween = create_tween()
	tween.tween_property(_fade_rect, "modulate:a", 0.0, duration)
	await tween.finished

# ---------------------------------------------------------------------------
# Async scene loading
# ---------------------------------------------------------------------------

func _load_scene_async(scene_path: String) -> void:
	# Request background loading.
	var error: Error = ResourceLoader.load_threaded_request(scene_path)
	if error != OK:
		push_error("SceneManager: failed to request threaded load for '%s' (error %d)." % [scene_path, error])
		_is_transitioning = false
		return

	# Poll until the resource is ready.
	var status: ResourceLoader.ThreadLoadStatus = ResourceLoader.THREAD_LOAD_IN_PROGRESS
	while status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		var progress: Array = []
		status = ResourceLoader.load_threaded_get_status(scene_path, progress)
		# Yield one frame to keep the engine responsive (fade stays visible).
		await get_tree().process_frame

	if status == ResourceLoader.THREAD_LOAD_FAILED:
		push_error("SceneManager: threaded load failed for '%s'." % scene_path)
		_is_transitioning = false
		return

	if status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		push_error("SceneManager: invalid resource at '%s'." % scene_path)
		_is_transitioning = false
		return

	var packed_scene: PackedScene = ResourceLoader.load_threaded_get(scene_path) as PackedScene
	if packed_scene == null:
		push_error("SceneManager: loaded resource at '%s' is not a PackedScene." % scene_path)
		_is_transitioning = false
		return

	get_tree().change_scene_to_packed(packed_scene)
