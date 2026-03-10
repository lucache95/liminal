shader_type canvas_item;

// Generates a flashlight cookie texture with soft radial falloff and noise.
// Render to a ViewportTexture and assign as a SpotLight3D projector texture.

uniform float edge_softness : hint_range(0.0, 1.0) = 0.4;
uniform float noise_amount : hint_range(0.0, 0.5) = 0.15;
uniform float hotspot_size : hint_range(0.0, 1.0) = 0.3;

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x),
		u.y
	);
}

void fragment() {
	vec2 centered = UV * 2.0 - 1.0;
	float dist = length(centered);

	// Radial falloff with hotspot
	float falloff = 1.0 - smoothstep(hotspot_size, 1.0 - edge_softness + hotspot_size, dist);

	// Subtle noise for realism (dirt, lens imperfections)
	float n = noise(UV * 12.0);
	falloff *= mix(1.0, n, noise_amount);

	// Clamp and output as white with alpha
	falloff = clamp(falloff, 0.0, 1.0);
	COLOR = vec4(vec3(falloff), falloff);
}
