// Turns a sprite's colours round the colour wheel and scales their saturation and brightness, for
// varying characters without new art. `ColorShift` sets it up and does the same maths on the CPU for
// anything that is not a sprite (the editor gizmo, corpses), so both agree.
//
// A hue *rotation* rather than a tint: a tint multiplies, so it can only darken, and a red body tinted
// blue turns brown. Rotating keeps the colours as clean as they were drawn.
//
// Lit like any other canvas item (no `unshaded`): an enemy must still vanish in the dark.
shader_type canvas_item;

// In turns: 1.0 is all the way round.
uniform float hue_shift = 0.0;
uniform float saturation = 1.0;
uniform float brightness = 1.0;

vec3 rgb_to_hsv(vec3 c) {
	vec4 k = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, k.wz), vec4(c.gb, k.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv_to_rgb(vec3 c) {
	vec3 p = abs(fract(c.xxx + vec3(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
	return c.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
}

void fragment() {
	// COLOR already holds the texture times the modulate, so hit flashes still come through.
	vec3 hsv = rgb_to_hsv(COLOR.rgb);
	hsv.x = fract(hsv.x + hue_shift);
	hsv.y = clamp(hsv.y * saturation, 0.0, 1.0);
	hsv.z *= brightness;
	COLOR.rgb = hsv_to_rgb(hsv);
}
