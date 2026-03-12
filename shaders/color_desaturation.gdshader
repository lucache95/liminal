shader_type canvas_item;

uniform float saturation : hint_range(0.0, 1.0) = 1.0;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;

void fragment() {
	vec4 color = texture(screen_texture, SCREEN_UV);
	// Perceptual luminance weights (ITU-R BT.601)
	float grey = dot(color.rgb, vec3(0.299, 0.587, 0.114));
	COLOR = vec4(mix(vec3(grey), color.rgb, saturation), 1.0);
}
