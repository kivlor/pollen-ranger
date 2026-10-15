class_name BlightSurface
extends Node
## Applies The Blight to any surface via a world-space corruption overlay.
##
## Drop this node under ANY prop (pot, trellis, ground, basket...) and it
## finds the MeshInstance3D targets, assigning a blight shader as a
## material_overlay so the original materials stay untouched.
##
## The corruption amount ("corruption" 0..1) drives how much of the surface
## the creeping gray ash has consumed, with purple/pink glowing cores.
##
## Feel goals (DESIGN.md):
## - Corruption should creep slowly, like rot taking hold
## - Cleansing should feel SATISFYING: punchy particle burst + audio cue
## - This is a garden reclaiming itself, not a horror game

signal corruption_changed(value: float)
signal fully_corrupted
signal cleansed

const BlightShader := preload("res://shaders/blight.gdshader")
const MotesScene := preload("res://scenes/effects/blight_motes.tscn")
const CleanseBurstScene := preload("res://scenes/effects/blight_cleanse_burst.tscn")

## Mesh root to corrupt. Leave empty to auto-target the parent node
## (all MeshInstance3D descendants get the overlay).
@export var target_path: NodePath

## How much of the surface the Blight has consumed (0 = clean, 1 = consumed)
@export_range(0.0, 1.0) var corruption: float = 0.0: set = set_corruption

## Should the corruption keep creeping over time?
@export var grow_over_time: bool = false

## Corruption gained per second while growing (slow, sickly)
@export_range(0.0, 1.0) var growth_rate: float = 0.02

## Corruption ceiling while growing
@export_range(0.0, 1.0) var max_corruption: float = 1.0

## Blight core pulse speed (cycles/sec) - slow and sickly
@export_range(0.0, 8.0) var pulse_speed: float = 0.5

## Purple/pink core glow strength
@export_range(0.0, 4.0) var core_glow: float = 1.4

## Scale of corruption blotches (smaller = bigger blotches)
@export var noise_scale: float = 0.9

## Give this surface its own corruption pattern?
@export var randomize_noise_offset: bool = true

## Optional cleanse sound. If unset, a generated placeholder chime is used.
@export var cleanse_sound: AudioStream

## How many ambient blight motes drift around the surface (scaled by size)
@export var mote_density: float = 1.0

var _material: ShaderMaterial
var _targets: Array[MeshInstance3D] = []
var _motes: GPUParticles3D
var _audio: AudioStreamPlayer3D
var _cleansing: bool = false


## Convenience: attach a BlightSurface to any node from code.
static func apply_to(target: Node, initial_corruption: float = 0.0) -> BlightSurface:
	var surface := BlightSurface.new()
	surface.corruption = initial_corruption
	target.add_child(surface)
	return surface


func _ready() -> void:
	add_to_group("blight_surface")
	_collect_targets()
	_apply_overlay()
	_setup_audio()
	_apply_corruption(corruption)


func _collect_targets() -> void:
	_targets.clear()
	var root: Node = null
	if not target_path.is_empty():
		root = get_node_or_null(target_path)
	if root == null:
		root = get_parent()
	if root == null:
		push_warning("BlightSurface has no target (no parent found)")
		return

	if root is MeshInstance3D:
		_targets.append(root)
	else:
		for child in root.find_children("*", "MeshInstance3D", true, false):
			_targets.append(child)

	if _targets.is_empty():
		push_warning("BlightSurface found no MeshInstance3D under %s" % root.name)


func _apply_overlay() -> void:
	# One shared material per surface: all meshes of a prop corrupt together.
	_material = ShaderMaterial.new()
	_material.shader = BlightShader
	if randomize_noise_offset:
		_material.set_shader_parameter("noise_offset",
				Vector3(randf() * 10.0, randf() * 10.0, randf() * 10.0))
	_material.set_shader_parameter("pulse_speed", pulse_speed)
	_material.set_shader_parameter("core_glow", core_glow)
	_material.set_shader_parameter("noise_scale", noise_scale)
	for target in _targets:
		target.material_overlay = _material


func _setup_audio() -> void:
	_audio = AudioStreamPlayer3D.new()
	_audio.name = "CleanseAudio"
	# Placeholder audio cue: a generated shimmer chime until a real SFX lands.
	_audio.stream = cleanse_sound if cleanse_sound else _generate_placeholder_chime()
	_audio.volume_db = -4.0
	_audio.max_distance = 40.0
	add_child(_audio)


## Generates a short rising shimmer - placeholder until real SFX is added.
func _generate_placeholder_chime() -> AudioStreamWAV:
	var sample_rate := 22050
	var duration := 0.7
	var num_samples := int(sample_rate * duration)
	var data := PackedByteArray()
	data.resize(num_samples * 2)
	for i in num_samples:
		var t := float(i) / float(sample_rate)
		# Rising pitch + second partial = glassy "purified" feel
		var freq := 440.0 + 660.0 * t
		var envelope := exp(-4.0 * t)
		var value := sin(TAU * freq * t) * 0.5 \
				+ sin(TAU * freq * 1.5 * t) * 0.25
		var sample := int(clampf(value * envelope, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, sample)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = sample_rate
	wav.stereo = false
	wav.data = data
	return wav


func set_corruption(value: float) -> void:
	var new_value: float = clampf(value, 0.0, 1.0)
	if is_equal_approx(new_value, corruption) and _material != null:
		return
	var was_blighted := is_blighted()
	corruption = new_value
	_apply_corruption(new_value)
	corruption_changed.emit(new_value)
	if not was_blighted and is_blighted():
		_ensure_motes()
	if new_value >= max_corruption - 0.001:
		fully_corrupted.emit()


func _apply_corruption(value: float) -> void:
	if _material != null:
		_material.set_shader_parameter("corruption", value)
	_update_motes()


func _update_motes() -> void:
	if corruption > 0.05 and not _cleansing:
		_ensure_motes()
		if _motes:
			_motes.amount_ratio = clampf(corruption * mote_density, 0.0, 1.0)
	elif _motes:
		_motes.emitting = false


func _ensure_motes() -> void:
	if _motes != null:
		return
	var center: Vector3
	var size: Vector3
	_surface_bounds(center, size)
	if size.length() < 0.001:
		return
	_motes = MotesScene.instantiate()
	add_child(_motes)
	_motes.position = center
	_motes.amount = maxi(8, int(size.length() * 6.0 * mote_density))
	var process_mat: ParticleProcessMaterial = _motes.process_material.duplicate()
	_motes.process_material = process_mat
	# Box roughly covering the corrupted surface
	process_mat.emission_box_extents = Vector3(
			maxf(size.x * 0.5, 0.3),
			maxf(size.y * 0.5, 0.3),
			maxf(size.z * 0.5, 0.3))


## Purges the Blight from this surface with a satisfying burst.
## This is THE moment of the game - make it punchy.
func cleanse() -> void:
	if _cleansing or corruption <= 0.001:
		return
	_cleansing = true

	# Punchy particle burst at the surface center
	var center: Vector3
	_surface_bounds(center, Vector3.ZERO)
	var burst := CleanseBurstScene.instantiate()
	get_tree().current_scene.add_child(burst)
	burst.global_position = center

	# Audio cue (placeholder chime unless a real SFX is assigned)
	if _audio:
		_audio.play()

	# Corruption burns away quickly - the color "returns" underneath
	var tween := create_tween()
	tween.tween_method(set_corruption, corruption, 0.0, 0.4) \
			.set_ease(Tween.EASE_OUT)
	tween.tween_callback(func() -> void:
		_cleansing = false
		if _motes:
			# Let lingering motes finish fading before cleanup
			_motes.emitting = false
			get_tree().create_timer(4.0).timeout.connect(
					func() -> void:
						if is_instance_valid(_motes):
							_motes.queue_free()
							_motes = null)
		cleansed.emit())


## True if any meaningful corruption remains on this surface.
func is_blighted() -> bool:
	return corruption > 0.01


## Combined world-space AABB of all target meshes.
func _surface_bounds(out_center: Vector3, out_size: Vector3) -> void:
	var merged := AABB()
	var first := true
	for target in _targets:
		var aabb: AABB = target.global_transform * target.get_aabb()
		if first:
			merged = aabb
			first = false
		else:
			merged = merged.merge(aabb)
	out_center = merged.get_center()
	out_size = merged.size


func _process(delta: float) -> void:
	# Corruption creeps slowly, like rot taking hold
	if grow_over_time and not _cleansing and corruption < max_corruption:
		set_corruption(minf(corruption + growth_rate * delta, max_corruption))
