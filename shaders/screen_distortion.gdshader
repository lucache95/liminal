shader_type canvas_item;

uniform float strength : hint_range(0.0, 0.1) = 0.0;
uniform float speed : hint_range(0.0, 5.0) = 1.0;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;

void fragment() {
	vec2 uv = SCREEN_UV;
	if (strength > 0.001) {
		// Sinusoidal UV displacement — wavy breathing effect
		float wave_x = sin(uv.y * 12.0 + TIME * speed) * strength;
		float wave_y = cos(uv.x * 10.0 + TIME * speed * 0.8) * strength * 0.7;
		uv += vec2(wave_x, wave_y);
	}
	COLOR = texture(screen_texture, uv);
}
