shader_type canvas_item;

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float diamond_size : hint_range(1.0, 50.0) = 10.0;
uniform vec4 fade_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);

void fragment() {
	// Diamond/pixelate dissolve pattern
	vec2 pixel_size = SCREEN_PIXEL_SIZE;
	vec2 screen_size = 1.0 / pixel_size;

	// Create diamond grid
	vec2 uv = UV * screen_size / diamond_size;
	vec2 diamond_uv = abs(fract(uv) - 0.5);
	float diamond = diamond_uv.x + diamond_uv.y;

	// Distance from center for radial wipe (0 at center, 1 at corners)
	vec2 center_dist = abs(UV - vec2(0.5)) * 2.0;
	float radial = max(center_dist.x, center_dist.y);

	// Combine diamond pattern with radial distance
	float threshold = mix(-0.5, 1.5, progress);
	float pattern = (diamond + radial) * 0.5;

	// Step creates hard pixel edges (pixelate dissolve look)
	float alpha = step(pattern, threshold);

	COLOR = vec4(fade_color.rgb, alpha * fade_color.a);
}
