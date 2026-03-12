@tool
class_name PerformanceValidator
extends Node

## Logs performance metrics for optimization validation.
## Add to any scene or call from town.gd in debug builds.


static func log_metrics() -> void:
	var fps: int = Engine.get_frames_per_second()
	var draw_calls: int = RenderingServer.get_rendering_info(
		RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME
	)
	var objects: int = RenderingServer.get_rendering_info(
		RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME
	)
	var vram_tex: int = RenderingServer.get_rendering_info(
		RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED
	)
	var vram_buf: int = RenderingServer.get_rendering_info(
		RenderingServer.RENDERING_INFO_BUFFER_MEM_USED
	)
	var vram_total: int = (vram_tex + vram_buf) / (1024 * 1024)

	print("=== PERFORMANCE METRICS ===")
	print("  FPS: %d" % fps)
	print("  Draw calls: %d" % draw_calls)
	print("  Objects in frame: %d" % objects)
	print("  VRAM (tex+buf): %d MB" % vram_total)
	print("  Target: 60 FPS, <4096 MB VRAM")

	if fps < 60:
		push_warning("PerformanceValidator: FPS below target (%d < 60)" % fps)
	if vram_total > 4096:
		push_warning("PerformanceValidator: VRAM above target (%d MB > 4096 MB)" % vram_total)
