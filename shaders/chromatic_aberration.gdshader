shader_type canvas_item;

uniform float strength : hint_range(0.0, 0.05) = 0.0;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;

void fragment() {
	if (strength > 0.001) {
		vec2 uv = SCREEN_UV;
		// Offset red channel left, blue channel right
		float r = texture(screen_texture, vec2(uv.x - strength, uv.y)).r;
		float g = texture(screen_texture, uv).g;
		float b = texture(screen_texture, vec2(uv.x + strength, uv.y)).b;
		COLOR = vec4(r, g, b, 1.0);
	} else {
		COLOR = texture(screen_texture, SCREEN_UV);
	}
}
