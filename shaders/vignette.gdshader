shader_type canvas_item;

uniform float intensity : hint_range(0.0, 1.0) = 0.4;
uniform float softness : hint_range(0.0, 1.0) = 0.5;
uniform vec4 color : source_color = vec4(0.0, 0.0, 0.0, 1.0);

void fragment() {
	vec2 uv = UV;
	// Distance from center (0,0 at center, ~0.707 at corners)
	float dist = distance(uv, vec2(0.5));
	// Normalize so edges are ~1.0
	float vignette = smoothstep(0.5 - softness * 0.5, 0.5 + softness * 0.5, dist * (1.0 + intensity));
	vignette = clamp(vignette * intensity * 2.0, 0.0, 1.0);
	COLOR = vec4(color.rgb, vignette * color.a);
}
