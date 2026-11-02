shader_type canvas_item;
render_mode blend_mix, unshaded;

// Wall fill: the surface texture, multiplied by how lit each part of the wall is.
//
// How lit it is arrives as a *vertex colour* rather than being sampled here. The lighting mask is a
// photograph of the level's lighting, and a wall is an occluder, so the mask on top of a wall is that
// wall's own shadow -- sampling it per pixel can only ever answer "how shadowed am I", which is why
// per-pixel attempts needed rings and probes and produced doubled shadows. Baking the value per vertex
// from the merged outline (see `WallFill`) means the geometry asks the question once, in the one place
// that knows where "outside the wall" is, and the GPU just interpolates.
uniform sampler2D albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform vec2 tile_world = vec2(64.0, 64.0);
uniform vec4 tint : source_color = vec4(1.0);
uniform float breakup_amount = 0.25;
uniform float breakup_scale = 0.21;
uniform float breakup_mask_scale = 6.0;

varying vec2 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX.xy, 0.0, 1.0)).xy;
}

void fragment() {
	vec2 uv = world_pos / tile_world;
	vec3 fine = texture(albedo, uv).rgb;
	vec3 wide = texture(albedo, uv * breakup_scale + vec2(0.37, 0.61)).rgb;
	// The coarse sample masks the blend, so tiling is broken up without needing a second texture.
	vec3 coarse = texture(albedo, uv / breakup_mask_scale).rgb;
	float mask = clamp(dot(coarse, vec3(0.299, 0.587, 0.114)) * 1.6, 0.0, 1.0);
	vec3 col = mix(fine, wide, breakup_amount * mask) * tint.rgb;

	// COLOR.r is the baked lighting for this vertex.
	COLOR = vec4(col * COLOR.r, 1.0);
}
