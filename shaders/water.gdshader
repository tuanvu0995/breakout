shader_type canvas_item;

uniform vec4 tint : source_color = vec4(1.0);
uniform float blur_amount = 1.0;

void fragment() {
	vec4 color = texture(TEXTURE, SCREEN_UV, blur_amount);

	color = mix(color, tint, 0.4);
	color = mix(vec4(0.5), color, 1.4);

	COLOR = color;
}