shader_type canvas_item;
render_mode blend_mix, unshaded;

// A surface that ignores the lighting system. Used by wall tops.
//
// Not a shortcut: a wall casts the shadows the whole vision model depends on, and in Godot 2D a
// rectangle's own interior is always behind one of its edges, so a wall can never be lit by the light it
// occludes. Instead of lighting the wall, this samples `RevealMask` -- a low-resolution photograph of the
// level's lighting, in which the player's cone and the lamps have already done their work, shadows and
// all -- and multiplies the wall by it. A wall is therefore visible exactly where it is lit, and a long
// wall shows only the lit stretch of itself.
#include "res://src/levels/surface_common.gdshaderinc"

uniform sampler2D reveal : hint_default_white, filter_linear, repeat_disable;
uniform vec2 reveal_origin = vec2(0.0);
uniform vec2 reveal_size = vec2(1.0);
// How far outside the wall the mask is read. Reading *at* the wall would read its own shadow: a wall is
// an occluder, so the lighting photographed on top of it is darkness.
uniform float reveal_probe = 10.0;

void fragment() {
	vec3 col = surface_color();
	// Step out through the nearest edge to ask "how lit is the space beside this wall, here". That is the
	// closest thing to lighting a surface that casts its own shadow can have.
	vec2 edge_distance = size_world * 0.5 - abs(local_pos);
	vec2 outward = edge_distance.x < edge_distance.y
		? vec2(sign(local_pos.x + 0.0001), 0.0)
		: vec2(0.0, sign(local_pos.y + 0.0001));
	vec2 probe = world_pos + outward * (min(edge_distance.x, edge_distance.y) + reveal_probe);
	vec2 reveal_uv = clamp((probe - reveal_origin) / reveal_size, vec2(0.0), vec2(1.0));
	float lit = texture(reveal, reveal_uv).r;
	COLOR = vec4(col * lit, 1.0);
}
