// Circular scope overlay for the arm-cannon zoom (issue #9).
// Draws a soft circular mask: clear center, subtle vignette toward the
// rim, darkened glass outside the circle, and a calm crosshair reticle.
// Should feel like MDK's sniper scope: steady and precise, not busy.
shader_type canvas_item;

// width / height of the overlay rect, set from the script so the scope
// circle stays perfectly round at any window size.
uniform float aspect = 1.7778;

// Scope circle radius, where 1.0 = half the screen height.
uniform float scope_radius : hint_range(0.1, 0.9) = 0.62;
// How wide the blur band is between clear center and darkened edges.
uniform float edge_softness : hint_range(0.01, 0.3) = 0.1;

uniform vec4 vignette_color : source_color = vec4(0.02, 0.06, 0.04, 1.0);
uniform vec4 reticle_color : source_color = vec4(0.62, 0.95, 0.65, 1.0);

void fragment() {
	// p: -1..1 vertically across the screen height, aspect-corrected.
	vec2 p = (SCREEN_UV - 0.5) * 2.0;
	p.x *= aspect;
	float d = length(p);

	// Mask: 0 inside the scope circle, 1 outside it.
	float outside = smoothstep(scope_radius, scope_radius + edge_softness, d);

	// Subtle vignette inside the circle (darkens toward the rim only).
	float rim = clamp((d - scope_radius * 0.72) / max(scope_radius * 0.28, 0.001), 0.0, 1.0);
	float inner_vignette = rim * 0.4;

	// Heavier darkened glass outside the scope circle.
	float outer_shade = 0.78 * outside;
	float shade_alpha = max(inner_vignette, outer_shade);

	// Crosshair: thin lines with a center gap, plus a small center dot
	// and a faint ring tracing the scope rim.
	float thickness = 0.006;
	float gap = 0.07;
	float line_len = scope_radius * 0.82;
	float line_h = smoothstep(thickness, thickness * 0.4, abs(p.y))
			* step(gap, abs(p.x)) * step(abs(p.x), line_len);
	float line_v = smoothstep(thickness, thickness * 0.4, abs(p.x))
			* step(gap, abs(p.y)) * step(abs(p.y), line_len);
	float dot_m = smoothstep(0.008, 0.004, d);
	float ring = smoothstep(0.004, 0.001, abs(d - scope_radius)) * 0.5;
	float reticle = clamp(line_h + line_v + dot_m + ring, 0.0, 1.0);

	vec4 col = vignette_color;
	col.rgb = mix(vignette_color.rgb, reticle_color.rgb, reticle);
	col.a = clamp(max(shade_alpha, reticle * 0.9), 0.0, 1.0);
	COLOR = col;
}
