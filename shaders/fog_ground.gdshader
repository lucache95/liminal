shader_type spatial;
render_mode unshaded, blend_add, cull_disabled;

uniform vec4 fog_color : source_color = vec4(0.7, 0.75, 0.8, 0.3);
uniform float density : hint_range(0.0, 1.0) = 0.5;
uniform float height_falloff : hint_range(0.1, 5.0) = 1.0;
uniform float scroll_speed : hint_range(0.0, 2.0) = 0.3;

// Procedural noise functions (no texture dependency)
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	// Smooth interpolation
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash(i + vec2(0.0, 0.0)), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x),
		u.y
	);
}

float fbm(vec2 p) {
	float value = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < 4; i++) {
		value += amplitude * noise(p);
		p *= 2.0;
		amplitude *= 0.5;
	}
	return value;
}

void vertex() {
	// Pass world position via VERTEX (already in model space, transform for fragment)
}

void fragment() {
	// Get world position from vertex
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

	// Scrolling noise based on world position
	vec2 noise_uv = world_pos.xz * 0.1 + vec2(TIME * scroll_speed * 0.3, TIME * scroll_speed * 0.2);
	float fog_noise = fbm(noise_uv);

	// Distance-based fade from camera
	float dist = length(world_pos - CAMERA_POSITION_WORLD);
	float distance_fade = 1.0 - smoothstep(5.0, 40.0, dist);

	// Height-based falloff
	float height_fade = exp(-abs(world_pos.y) * height_falloff);

	// Combine all factors
	float alpha = fog_noise * density * distance_fade * height_fade * fog_color.a;
	alpha = clamp(alpha, 0.0, 1.0);

	ALBEDO = fog_color.rgb;
	ALPHA = alpha;
}
