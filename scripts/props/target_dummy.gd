class_name TargetDummy
extends StaticBody3D
## A static blight-bud target for the tutorial shooting range.
##
## A corrupted flower bud on a wooden stake. One seed hit bursts it into
## a cleansing bloom; it re-grows after a short delay so the range never
## runs dry. Pure practice — it never fights back.
##
## Feel goals (DESIGN.md):
## - Hitting it should feel punchy: flash + squash on hit, bloom burst on pop
## - The re-grow keeps the tutorial loop going without player input

signal target_destroyed(target: TargetDummy)

## Health — one standard seed hit (10 damage) pops the bud
@export var max_health: int = 10

## Seconds before the bud re-grows after being popped
@export var respawn_delay: float = 4.0

@onready var _visual: Node3D = $Visual
@onready var _collision: CollisionShape3D = $CollisionShape3D
@onready var _bud_mesh: MeshInstance3D = $Visual/Bud

const CLEANSE_BURST_SCENE := preload("res://scenes/effects/blight_cleanse_burst.tscn")

var _health: int
var _bud_material: StandardMaterial3D
var _hit_tween: Tween
var _respawn_timer: SceneTreeTimer


func _ready() -> void:
	## Targets sit on the environment layer so seeds (mask 2) hit them
	collision_layer = 2
	collision_mask = 0
	add_to_group("targets")

	_health = max_health

	## Duplicate the bud material so hit flashes don't affect every target
	_bud_material = _bud_mesh.get_active_material(0).duplicate()
	_bud_mesh.set_surface_override_material(0, _bud_material)


func take_damage(amount: int) -> void:
	## Called by seed projectiles on impact
	if _health <= 0:
		return

	_health -= amount

	if _health <= 0:
		_pop_bud()
	else:
		_hit_flash()


func _hit_flash() -> void:
	## Pain feedback: pale flash + squash-and-stretch wobble
	if _hit_tween != null and _hit_tween.is_valid():
		_hit_tween.kill()

	_bud_material.albedo_color = Color(1.0, 0.85, 1.0)
	_visual.scale = Vector3(1.2, 0.75, 1.2)

	_hit_tween = create_tween()
	_hit_tween.set_parallel(true)
	_hit_tween.tween_property(_bud_material, "albedo_color",
			Color(0.55, 0.35, 0.85), 0.3)
	_hit_tween.set_parallel(false)
	_hit_tween.tween_property(_visual, "scale", Vector3.ONE, 0.25) \
			.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func _pop_bud() -> void:
	## The satisfying part: bud bursts into a cleansing bloom, then re-grows
	_visual.visible = false
	_collision.set_deferred("disabled", true)

	var burst: Node3D = CLEANSE_BURST_SCENE.instantiate()
	get_tree().current_scene.add_child(burst)
	burst.global_position = global_position + Vector3.UP * 1.0

	target_destroyed.emit(self)

	_respawn_timer = get_tree().create_timer(respawn_delay)
	_respawn_timer.timeout.connect(_regrow)


func _regrow() -> void:
	## Fresh bud — the blight keeps creeping back on the range
	if not is_inside_tree():
		return

	_health = max_health
	_visual.visible = true
	_collision.set_deferred("disabled", false)

	## Re-grow with a springy pop
	_visual.scale = Vector3(0.1, 0.1, 0.1)
	var tween := create_tween()
	tween.tween_property(_visual, "scale", Vector3.ONE, 0.4) \
			.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
