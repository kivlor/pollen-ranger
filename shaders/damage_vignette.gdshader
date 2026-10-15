shader_type canvas_item;
// Damage vignette for the health HUD (issue #8).
// A soft red vignette that darkens the edges of the screen as the player
// loses health - "how close to death am I" should be readable without
// staring at the hearts. HUD drives `intensity` every frame:
//   missing-health fraction + a pulse while at 1 heart (critical).

render_mode blend_premul_alpha;

// Red of the Blight-lash pain: deep bruised crimson, not horror-red
uniform vec4 tint : source_color = vec4(0.55, 0.02, 0.05, 1.0);

// 0.0 = invisible, 1.0 = vignette fully swallowed the edges
uniform float intensity : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 centered = UV - vec2(0.5);
	// Squared aspect-corrected distance so the vignette is elliptical on
	// wide screens (follows the window shape, not a circle clipped by it)
	vec2 shaped = centered * vec2(1.15, 1.0);
	float dist = length(shaped) * 2.0;

	// Ring that starts well outside the play area: edges only, soft falloff
	float ring = smoothstep(0.55, 1.35, dist);

	// A faint inner wash so at critical health the whole screen feels wrong
	float wash = smoothstep(0.25, 1.0, dist) * 0.35;

	COLOR = vec4(tint.rgb, tint.a * intensity * (ring + wash));
}
