shader_type canvas_item;

uniform float grain_amount : hint_range(0.0, 0.5) = 0.05;
uniform float grain_size : hint_range(1.0, 4.0) = 1.5;

// Hash-based pseudo-random noise (no texture needed)
float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	// Scale UV by grain_size and add TIME for animation
	vec2 grain_uv = UV * (1.0 / grain_size) * vec2(textureSize(TEXTURE, 0));
	float noise = hash(grain_uv + vec2(TIME * 137.0, TIME * 271.0));
	// Center noise around 0 (-0.5 to 0.5) and scale by amount
	float grain = (noise - 0.5) * grain_amount;
	// Additive blend with low opacity
	COLOR = vec4(vec3(grain), abs(grain) * 2.0);
}
