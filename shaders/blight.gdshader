shader_type spatial;
// The Blight - creeping gray corruption overlay for ANY surface.
// Applied as a GeometryInstance3D.material_overlay, so the underlying
// StandardMaterial3D stays untouched. The corruption creeps across the mesh
// in WORLD SPACE, meaning the pattern flows naturally around pots, trellises
// and ground regardless of UVs.
// Look goals (DESIGN.md):
// - Gray/ash-like corruption spreading across surfaces
// - Subtle purple/pink emission pulsing from Blight cores
// - Slow, creeping growth feel - never frozen, never frantic
// - Lighter "dust" at the creeping front, like ash falling off

render_mode blend_mix, depth_draw_never, cull_disabled, specular_disabled;

// === CORRUPTION AMOUNT ===
// 0.0 = clean surface, 1.0 = fully consumed by Blight
uniform float corruption : hint_range(0.0, 1.0) = 0.5;

// === COLORS ===
// Ash body of the corruption - gray with a cold violet cast
uniform vec4 ash_color : source_color = vec4(0.30, 0.28, 0.33, 1.0);
// Lighter dust at the creeping front, like ash flaking off
uniform vec4 edge_color : source_color = vec4(0.55, 0.50, 0.58, 1.0);
// Purple/pink glow of Blight cores (DESIGN.md: subtle purple/pink emission)
uniform vec3 core_color : source_color = vec3(0.65, 0.30, 0.80);
uniform float core_glow : hint_range(0.0, 4.0) = 1.4;

// === ANIMATION ===
// How fast cores pulse (cycles per second - should feel slow and sickly)
uniform float pulse_speed : hint_range(0.0, 8.0) = 0.5;
// How much the pulse dims/brightens cores (0 = steady glow)
uniform float pulse_strength : hint_range(0.0, 1.0) = 0.4;
// How fast the pattern creeps across the surface (world units/sec in noise space)
uniform float creep_speed : hint_range(0.0, 1.0) = 0.06;

// === NOISE SHAPE ===
// Scale of the corruption blotches in world space (smaller = bigger blotches)
uniform float noise_scale = 0.9;
// Offset so different props don't share identical patterns
uniform vec3 noise_offset = vec3(0.0);
// Width of the soft creeping-front band
uniform float edge_width : hint_range(0.0, 0.3) = 0.09;
// Graininess of the ash (crumbly, powdery detail)
uniform float grain_strength : hint_range(0.0, 1.0) = 0.18;

varying vec3 world_pos;

// --- Simplex noise (same implementation as soil.gdshader) ---
vec3 mod289(vec3 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
vec4 mod289(vec4 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
vec4 permute(vec4 x) { return mod289(((x * 34.0) + 1.0) * x); }
vec4 taylorInvSqrt(vec4 r) { return 1.79284291400159 - 0.85373472095314 * r; }

float snoise(vec3 v) {
	const vec2 C = vec2(1.0 / 6.0, 1.0 / 3.0);
	const vec4 D = vec4(0.0, 0.5, 1.0, 2.0);

	vec3 i = floor(v + dot(v, C.yyy));
	vec3 x0 = v - i + dot(i, C.xxx);

	vec3 g = step(x0.yzx, x0.xyz);
	vec3 l = 1.0 - g;
	vec3 i1 = min(g.xyz, l.zxy);
	vec3 i2 = max(g.xyz, l.zxy);

	vec3 x1 = x0 - i1 + C.xxx;
	vec3 x2 = x0 - i2 + C.yyy;
	vec3 x3 = x0 - D.yyy;

	i = mod289(i);
	vec4 p = permute(permute(permute(
		i.z + vec4(0.0, i1.z, i2.z, 1.0))
		+ i.y + vec4(0.0, i1.y, i2.y, 1.0))
		+ i.x + vec4(0.0, i1.x, i2.x, 1.0));

	float n_ = 0.142857142857;
	vec3 ns = n_ * D.wyz - D.xzx;

	vec4 j = p - 49.0 * floor(p * ns.z * ns.z);

	vec4 x_ = floor(j * ns.z);
	vec4 y_ = floor(j - 7.0 * x_);

	vec4 x = x_ * ns.x + ns.yyyy;
	vec4 y = y_ * ns.x + ns.xxxx;
	vec4 h = 1.0 - abs(x) - abs(y);

	vec4 b0 = vec4(x.xy, y.xy);
	vec4 b1 = vec4(x.zw, y.zw);

	vec4 s0 = floor(b0) * 2.0 + 1.0;
	vec4 s1 = floor(b1) * 2.0 + 1.0;
	vec4 sh = -step(h, vec4(0.0));

	vec4 a0 = b0.xzyw + s0.xzyw * sh.xxyy;
	vec4 a1 = b1.xzyw + s1.xzyw * sh.zzww;

	vec3 p0 = vec3(a0.xy, h.x);
	vec3 p1 = vec3(a0.zw, h.y);
	vec3 p2 = vec3(a1.xy, h.z);
	vec3 p3 = vec3(a1.zw, h.w);

	vec4 norm = taylorInvSqrt(vec4(dot(p0, p0), dot(p1, p1), dot(p2, p2), dot(p3, p3)));
	p0 *= norm.x;
	p1 *= norm.y;
	p2 *= norm.z;
	p3 *= norm.w;

	vec4 m = max(0.6 - vec4(dot(x0, x0), dot(x1, x1), dot(x2, x2), dot(x3, x3)), 0.0);
	m = m * m;
	return 42.0 * dot(m * m, vec4(dot(p0, x0), dot(p1, x1), dot(p2, p2), dot(p3, p3)));
}

// Fractal Brownian motion - layered noise for organic blotchy shapes
float fbm(vec3 p) {
	float value = 0.0;
	float amplitude = 0.5;
	for (int i = 0; i < 3; i++) {
		value += amplitude * snoise(p);
		p *= 2.1;
		amplitude *= 0.5;
	}
	return value;
}

void vertex() {
	// World-space sampling so corruption creeps across meshes without UVs
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// The pattern slowly creeps upward through the noise domain -
	// like rot climbing a pot or a trellis post.
	vec3 sample_pos = world_pos * noise_scale + noise_offset
			+ vec3(0.0, -TIME * creep_speed, 0.0);
	float n = fbm(sample_pos) * 0.5 + 0.5;

	// Corruption boundary with a gentle "breathing" wobble so it never
	// looks like a frozen stencil.
	float threshold = 1.0 - corruption + sin(TIME * 0.35) * 0.02;
	float coverage = smoothstep(threshold - edge_width, threshold + edge_width, n);
	ALPHA = coverage;

	// Grainy ash body - crumbly detail so it reads as powder, not plastic
	float grain = snoise(world_pos * 14.0 + noise_offset) * 0.5 + 0.5;
	vec3 ash = ash_color.rgb * (1.0 + (grain - 0.5) * grain_strength * 2.0);

	// Lighter dust band at the creeping front - the "leading edge" of rot
	float edge_band = clamp(1.0 - abs(n - threshold) / (edge_width * 2.0), 0.0, 1.0);
	ALBEDO = mix(ash, edge_color.rgb, edge_band * 0.7);
	ROUGHNESS = mix(0.9, 0.75, edge_band);

	// Blight cores: high-frequency pockets of purple/pink glow.
	// More corruption = more cores showing through the ash.
	float cn = fbm(world_pos * noise_scale * 2.2 + noise_offset * 1.7 + vec3(31.7)) * 0.5 + 0.5;
	float core_mask = smoothstep(0.60, 0.80, cn) * smoothstep(0.2, 0.9, corruption);

	// Slow sickly pulse, phase-shifted across the surface so cores don't
	// all blink in unison - feels like something alive under the ash.
	float pulse = mix(1.0 - pulse_strength, 1.0 + pulse_strength,
			0.5 + 0.5 * sin(TIME * pulse_speed * 6.2831853
					+ world_pos.x * 0.7 + world_pos.z * 0.9));
	EMISSION = core_color * core_mask * core_glow * pulse * coverage;
}
