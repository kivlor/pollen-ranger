shader_type spatial;
## Soil shader that blends between BLIGHT (gray/ash) and BLOOM (lush green) states
## Uses noise for organic-looking transitions and includes a glow effect when cleansed

// === STATE UNIFORMS ===
// Blend factor: 0.0 = full BLIGHT, 1.0 = full BLOOM
uniform float bloom_factor : hint_range(0.0, 1.0) = 0.0;

// Glow intensity for cleanse effect (0.0 = no glow, 1.0 = full glow)
uniform float glow_intensity : hint_range(0.0, 1.0) = 0.0;

// === COLOR UNIFORMS ===
// Blight colors - gray, ash, desaturated
uniform vec4 blight_albedo : source_color = vec4(0.35, 0.32, 0.35, 1.0);
uniform vec4 blight_emission : source_color = vec4(0.0, 0.0, 0.0, 1.0);

// Bloom colors - lush greens with subtle yellow undertones
uniform vec4 bloom_albedo : source_color = vec4(0.25, 0.45, 0.15, 1.0);
uniform vec4 bloom_emission : source_color = vec4(0.15, 0.25, 0.05, 1.0);

// Neutral soil color
uniform vec4 neutral_albedo : source_color = vec4(0.25, 0.18, 0.12, 1.0);

// === MATERIAL PROPERTIES ===
uniform float roughness : hint_range(0.0, 1.0) = 0.95;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;

// === NOISE PARAMETERS ===
// Time for animated noise
uniform float time = 0.0;
// Noise scale for organic edges
uniform float noise_scale = 4.0;
// Noise influence on blending (0 = sharp edge, 1 = very organic)
uniform float noise_influence : hint_range(0.0, 1.0) = 0.3;

// Simplex noise function (3D)
vec3 mod289(vec3 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
vec4 mod289(vec4 x) { return x - floor(x * (1.0 / 289.0)) * 289.0; }
vec4 permute(vec4 x) { return mod289(((x * 34.0) + 1.0) * x); }
vec4 taylorInvSqrt(vec4 r) { return 1.79284291400159 - 0.85373472095314 * r; }

float snoise(vec3 v) {
	const vec2 C = vec2(1.0/6.0, 1.0/3.0);
	const vec4 D = vec4(0.0, 0.5, 1.0, 2.0);

	// First corner
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
	return 42.0 * dot(m * m, vec4(dot(p0, x0), dot(p1, x1), dot(p2, x2), dot(p3, x3)));
}

void fragment() {
	// Generate noise for organic edges
	vec3 noise_pos = vec3(UV * noise_scale, time * 0.1);
	float noise_val = snoise(noise_pos) * 0.5 + 0.5; // Remap from [-1,1] to [0,1]
	
	// Calculate final blend factor with noise influence
	float effective_bloom = bloom_factor;
	if (noise_influence > 0.0) {
		// Only apply noise near the transition boundary
		float transition_edge = smoothstep(0.3, 0.7, bloom_factor);
		effective_bloom = mix(bloom_factor, bloom_factor * noise_val, noise_influence * (1.0 - abs(bloom_factor - 0.5) * 2.0));
	}
	
	// Smooth the transition
	float blend = smoothstep(0.0, 1.0, effective_bloom);
	
	// Determine base color based on state
	vec3 base_albedo;
	if (blend < 0.3) {
		// Mostly blight - blend between neutral and blight
		float t = blend / 0.3;
		base_albedo = mix(neutral_albedo.rgb, blight_albedo.rgb, t);
	} else if (blend < 0.7) {
		// Transition zone - interpolate directly
		base_albedo = mix(blight_albedo.rgb, bloom_albedo.rgb, (blend - 0.3) / 0.4);
	} else {
		// Mostly bloom
		float t = (blend - 0.7) / 0.3;
		base_albedo = mix(bloom_albedo.rgb, bloom_albedo.rgb * 1.1, t); // Slight brightening at full bloom
	}
	
	// Apply albedo
	ALBEDO = base_albedo;
	
	// Apply material properties
	ROUGHNESS = roughness;
	METALLIC = metallic;
	
	// Glow effect when cleansed
	vec3 glow_color = vec3(0.4, 0.6, 0.2); // Green-tinted glow
	EMISSION = glow_color * glow_intensity * 2.0;
}
