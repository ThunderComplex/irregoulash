shader_type canvas_item;
render_mode blend_mix, unshaded;

// A surface that ignores the lighting system. Used by wall tops.
//
// Not a shortcut: a wall casts the shadows the whole vision model depends on, and in Godot 2D a
// rectangle's own interior is always behind one of its edges, so a wall can never be lit by the light it
// occludes. Instead of lighting the wall, this samples `RevealMask` -- a low-resolution photograph of the
// level's lighting, in which the player's cone and the lamps have already done their work, shadows and
// all -- and multiplies the wall by it.
//
// The mask is read in a *ring* around each pixel rather than by stepping out through an edge, and that
// detail matters: a wall is built from rectangles, so at a join the nearest edge of the rectangle a pixel
// belongs to is an interior edge, shared with the next wall. Stepping out through it samples the
// neighbour's shadow, which showed up as a lit seam running along every join. A ring asks the question
// the design actually means -- "is the space around this part of the wall lit" -- and does not care how
// many rectangles the wall is made of.
#include "res://src/levels/surface_common.gdshaderinc"

uniform sampler2D reveal : hint_default_white, filter_linear, repeat_disable;
uniform vec2 reveal_origin = vec2(0.0);
uniform vec2 reveal_size = vec2(1.0);
// Extra reach beyond half the wall's thickness, so the ring clears the wall itself.
uniform float reveal_reach : hint_range(0.0, 96.0) = 4.0;
// Samples around the ring. Eight is enough to read as smooth at mask resolution.
uniform int reveal_samples : hint_range(4, 16) = 8;

float sample_mask(vec2 world_point) {
	vec2 uv = clamp((world_point - reveal_origin) / reveal_size, vec2(0.0), vec2(1.0));
	return texture(reveal, uv).r;
}

void fragment() {
	vec3 col = surface_color();
	// Half the *thinner* dimension plus a margin: that reaches past the wall from anywhere inside it,
	// including the centre of a thick block, without reaching across a room.
	float radius = min(size_world.x, size_world.y) * 0.5 + reveal_reach;
	float lit = sample_mask(world_pos);
	for (int i = 0; i < reveal_samples; i++) {
		float angle = (float(i) / float(reveal_samples)) * 6.28318530718;
		lit = max(lit, sample_mask(world_pos + vec2(cos(angle), sin(angle)) * radius));
	}
	COLOR = vec4(col * lit, 1.0);
}
