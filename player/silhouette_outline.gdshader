shader_type canvas_item;
// Draws a 1 px outline around the opaque pixels of a texture, inside its transparent margin.
// Used on the rig's render so the whole robot gets one silhouette outline: joints where parts
// overlap stay clean, and the thin limbs stay readable against dark backgrounds.

uniform vec4 outline_color : source_color = vec4(0.04, 0.04, 0.05, 1.0);

void fragment() {
	vec2 uv = UV;
	vec4 color = texture(TEXTURE, uv);
	if (color.a < 0.5) {
		vec2 px = TEXTURE_PIXEL_SIZE;
		float near = max(
			max(texture(TEXTURE, uv + vec2(px.x, 0.0)).a, texture(TEXTURE, uv - vec2(px.x, 0.0)).a),
			max(texture(TEXTURE, uv + vec2(0.0, px.y)).a, texture(TEXTURE, uv - vec2(0.0, px.y)).a)
		);
		if (near >= 0.5) {
			color = outline_color;
		}
	}
	COLOR = color;
}
