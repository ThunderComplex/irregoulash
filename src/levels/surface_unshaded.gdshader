shader_type canvas_item;
render_mode blend_mix, unshaded;

// A surface that ignores the lighting system. Used by wall tops.
//
// Not a shortcut: a wall casts the shadows the whole vision model depends on, and in Godot 2D a
// rectangle's own interior is always behind one of its edges, so a wall can never be lit by the light
// it occludes. Wall tops have therefore always been drawn by the unshaded "memory" silhouette -- the
// body underneath them contributed nothing at all. Giving the body this shader puts the surface where
// that silhouette was: the wall is still only visible once it has been seen, but what it is made of is
// now a texture instead of a flat colour.
#include "res://src/levels/surface_common.gdshaderinc"

void fragment() {
	COLOR = vec4(surface_color(), 1.0);
}
