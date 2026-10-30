// Shared body of the surface shaders. Included by `surface.gdshader` (lit: floors) and
// `surface_unshaded.gdshader` (unlit: wall tops), so the look of a surface is defined once.
//
// Tiling is in WORLD space, so one tile is 64 world pixels on a 96px wall and on a 2000px wall alike.
// Edge shading is in LOCAL space, so a rim, its ambient occlusion and the bottom band look identical
// whatever size the rectangle is. Keeping those two spaces apart is the whole design.
//
// Both positions arrive as varyings computed in the vertex stage rather than read from `VERTEX` in the
// fragment stage. A floor is one enormous quad, and anything that misreads the local position on a quad
// that size shows up as a rectangular patch of wrong shading across the screen.

uniform sampler2D albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform vec2 tile_world = vec2(64.0, 64.0);
// Explicit rather than taken from the Polygon2D's colour: relying on the vertex colour silently did
// nothing, and a surface tint that cannot be changed is worse than one more uniform.
uniform vec4 tint : source_color = vec4(1.0);

// Tiling across a big surface is broken up by blending a second, much larger sample of the same texture.
// The mask is that sample itself, so no extra texture is needed and there is no unassigned sampler to
// depend on.
uniform float breakup_amount = 0.35;
uniform float breakup_scale = 0.23;
uniform float breakup_mask_scale = 6.0;

// The surface's own size in world pixels, needed for the edge treatment.
uniform vec2 size_world = vec2(64.0, 64.0);
// A bright edge, and light falling off just inside it. Together these are what read as thickness from
// above -- more than any texture detail does. Both are off for floors: a floor has no rim.
uniform float rim_width = 0.0;
uniform float rim_boost = 0.0;
uniform float rim_ao_width = 14.0;
uniform float rim_ao_strength = 0.0;
// Fraction of the height darkened at the bottom edge, faking the drop into the wall's face.
uniform float base_band = 0.0;
uniform float base_strength = 0.0;

varying vec2 world_pos;
varying vec2 local_pos;

void vertex() {
	// `VERTEX` is a vec3 in the vertex stage of a canvas_item shader, so take .xy explicitly.
	local_pos = VERTEX.xy;
	world_pos = (MODEL_MATRIX * vec4(VERTEX.xy, 0.0, 1.0)).xy;
}

vec3 surface_color() {
	vec2 uv = world_pos / tile_world;
	vec3 fine = texture(albedo, uv).rgb;
	vec3 wide = texture(albedo, uv * breakup_scale + vec2(0.37, 0.61)).rgb;
	vec3 coarse = texture(albedo, uv / breakup_mask_scale).rgb;
	// Use the coarse sample's brightness as its own mask: where it is dark, lean on the wide sample; where
	// it is bright, keep the fine detail.
	float mask = clamp(dot(coarse, vec3(0.299, 0.587, 0.114)) * 1.6, 0.0, 1.0);
	vec3 col = mix(fine, wide, breakup_amount * mask) * tint.rgb;

	// Distance to the nearest edge, in world pixels.
	vec2 from_edge = size_world * 0.5 - abs(local_pos);
	float edge = max(min(from_edge.x, from_edge.y), 0.0);

	// Capped by the surface's smallest dimension: a 32px-thick wall must not end up entirely shadow
	// because its rim is 14px wide on all four sides.
	float ao = min(rim_ao_width, min(size_world.x, size_world.y) * 0.35);
	col *= 1.0 - (1.0 - smoothstep(0.0, max(ao, 0.001), edge)) * rim_ao_strength;

	if (base_band > 0.0 && base_strength > 0.0) {
		float down = clamp(local_pos.y / size_world.y + 0.5, 0.0, 1.0);
		col *= 1.0 - smoothstep(1.0 - base_band, 1.0, down) * base_strength;
	}

	if (rim_boost > 0.0 && rim_width > 0.0) {
		// Bright edge last, so it sits on top of its own occlusion. Proportional rather than additive so
		// the rim keeps the texture's hue, which is what makes it look lit instead of painted on.
		float rim = 1.0 - smoothstep(0.0, rim_width, edge);
		col += col * (rim * rim_boost);
	}
	return col;
}
