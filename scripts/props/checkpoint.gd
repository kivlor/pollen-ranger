class_name Checkpoint
extends Area3D
## Checkpoint bloom — a respawn point in the level (issue #8).
##
## A closed seed-bud on a stem. When the player walks into its trigger
## volume it BLOOMS: the bud opens golden, light spills out, and the
## player's respawn moves here (levels listen to `activated`).
##
## Checkpoints don't heal on touch — health is restored on respawn —
## so the system stays "punishing but fair" (issue #8 design notes).
##
## Zero-config: drop a checkpoint anywhere in a level. The level script
## finds them via the "checkpoint" group.

signal activated(checkpoint: Checkpoint)

## Where the player is placed when respawning here (relative to the bud)
@export var respawn_offset: Vector3 = Vector3(0, 0.4, 0)

## Trigger volume size (player must physically walk through it)
@export var trigger_size: Vector3 = Vector3(3.0, 3.0, 3.0)

var is_active: bool = false

@onready var _stem: MeshInstance3D = $Visual/Stem
@onready var _bud: MeshInstance3D = $Visual/Bud
@onready var _glow: OmniLight3D = $Visual/Glow
@onready var _sfx: AudioStreamPlayer = $SFX

var _bloom_material: StandardMaterial3D

## Closed-bud / bloomed look
const BUD_CLOSED := Color(0.45, 0.55, 0.35)     # pale green husk
const BUD_BLOOMED := Color(0.98, 0.82, 0.35)    # warm golden bloom
const GLOW_ENERGY_CLOSED := 0.4
const GLOW_ENERGY_BLOOMED := 1.6


func _ready() -> void:
	add_to_group("checkpoint")

	## Trigger watches for the player body only
	collision_layer = 0
	collision_mask = 1
	var shape := BoxShape3D.new()
	shape.size = trigger_size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	add_child(collision)
	body_entered.connect(_on_body_entered)

	## Duplicate the bud material so blooming one checkpoint doesn't
	## re-tint every checkpoint instance
	var mat: Material = _bud.get_active_material(0)
	if mat is StandardMaterial3D:
		_bloom_material = mat.duplicate()
		_bud.set_surface_override_material(0, _bloom_material)
		_bloom_material.albedo_color = BUD_CLOSED
		_bloom_material.emission_enabled = true
		_bloom_material.emission = BUD_CLOSED
		_bloom_material.emission_energy_multiplier = 0.4

	_glow.light_energy = GLOW_ENERGY_CLOSED


func _on_body_entered(body: Node3D) -> void:
	if is_active or not body.is_in_group("player"):
		return
	_bloom()


func _bloom() -> void:
	## First touch claims the checkpoint: pop open golden and report in.
	is_active = true
	activated.emit(self)
	_sfx.play()

	if _bloom_material != null:
		_bloom_material.albedo_color = BUD_BLOOMED
		_bloom_material.emission = BUD_BLOOMED

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(_glow, "light_energy", GLOW_ENERGY_BLOOMED, 0.4) \
			.set_ease(Tween.EASE_OUT)
	## Bud pops open (scale bounce)
	_bud.scale = Vector3.ONE * 0.6
	tween.tween_property(_bud, "scale", Vector3.ONE * 1.15, 0.25) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_bud, "scale", Vector3.ONE, 0.2)


func spawn_position() -> Vector3:
	return global_position + respawn_offset
