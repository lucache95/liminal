shader_type canvas_item;

uniform float strength : hint_range(0.0, 0.05) = 0.0;
uniform float speed : hint_range(0.1, 3.0) = 0.8;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;

void fragment() {
	vec2 uv = SCREEN_UV;
	if (strength > 0.001) {
		// Slow sinusoidal zoom from center -- "breathing" effect
		float pulse = sin(TIME * speed * 2.0 * PI) * 0.5 + 0.5;
		float scale = 1.0 + pulse * strength;
		uv = (uv - 0.5) / scale + 0.5;
	}
	COLOR = texture(screen_texture, uv);
}
