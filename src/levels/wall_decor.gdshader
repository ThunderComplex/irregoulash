shader_type canvas_item;
render_mode blend_mix, unshaded;

// Rim and occlusion for wall outlines. The colours arrive as vertex colours (rim, occlusion and south
// shadow are built as geometry by `WallDecor`); this only multiplies them by the same lighting mask the
// wall fill uses, so decoration appears exactly where the wall it belongs to is lit.
uniform sampler2D reveal : hint_default_white, filter_linear, repeat_disable;
uniform vec2 reveal_origin = vec2(0.0);
uniform vec2 reveal_size = vec2(1.0);

varying vec2 world_pos;

void vertex() {
	// `VERTEX` is a vec3 in the vertex stage; there is no `MODEL_MATRIX` in the fragment stage, so the
	// world position has to be carried across as a varying.
	world_pos = (MODEL_MATRIX * vec4(VERTEX.xy, 0.0, 1.0)).xy;
}

void fragment() {
	vec2 reveal_uv = clamp((world_pos - reveal_origin) / reveal_size, vec2(0.0), vec2(1.0));
	float lit = texture(reveal, reveal_uv).r;
	COLOR.rgb *= lit;
	COLOR.a *= lit;
}
