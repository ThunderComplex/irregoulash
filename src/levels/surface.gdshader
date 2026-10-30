shader_type canvas_item;
render_mode blend_mix;

// A surface that receives light from the game's lamps and the player's cone. Used by floors, which are
// the one thing light actually reaches.
#include "res://src/levels/surface_common.gdshaderinc"

void fragment() {
	COLOR = vec4(surface_color(), 1.0);
}
