class_name BlightedGrub
extends CharacterBody3D
## Blighted Grub — the greenhouse's first tier of corrupted wildlife.
##
## A thumb-length-and-then-some (0.5-1m) caterpillar consumed by The Blight:
## gray/ash body, glowing purple blight spots, sluggish and twitchy.
##
## Behavior:
## - Slow back-and-forth patrol between two ground waypoints (distance-based)
## - Proximity detection: notices the player nearby and agitates toward them
## - Contact damage via a slightly oversized Area3D (no ranged attack)
## - Dies when hit by seed projectiles, bursting into a cleansing particle burst
##
## Feel goals (DESIGN.md):
## - Sluggish, corrupted, slightly twitchy — never threatening in speed
## - The inchworm body-bob and random twitches sell the "wrongness" of The Blight
## - Death should feel like a tiny reclamation: ash + purple sparks + bloom pollen

signal health_changed(current_health: int, max_health: int)
signal died(grub: BlightedGrub)

enum State { PATROL, CHASE, DEAD }

## === COMBAT ===
## Health — one seed hit kills (seed projectile deals 10).
## Grubs are weak trash mobs; a single clean shot should feel punchy.
@export var max_health: int = 10

## Damage dealt to the player on contact
@export var contact_damage: int = 1

## Seconds between contact damage ticks while touching the player
@export var damage_cooldown: float = 1.2

## === PATROL ===
## Total distance covered in one direction before turning around
@export var patrol_distance: float = 4.0

## Sluggish patrol speed — the grub should never outrun a walking player
@export var patrol_speed: float = 1.2

## Agitated speed when the player is detected (still slow, still catchable)
@export var chase_speed: float = 2.4

## === DETECTION ===
## Player proximity that wakes the grub up
@export var detect_radius: float = 5.0

## Distance at which the grub gives up and returns to patrol
@export var lose_radius: float = 7.5

## How fast the grub steers/accelerates toward its desired direction
## Low values = heavy, sluggish, corrupted feel
@export var steering_acceleration: float = 3.0

## === REFERENCES ===
@onready var _visual: Node3D = $Visual
@onready var _collision_shape: CollisionShape3D = $CollisionShape3D
@onready var _damage_area: Area3D = $DamageArea
@onready var _glow_light: OmniLight3D = $Visual/GlowLight

## Reusable cleanse burst — grub death is a tiny "reclamation" moment
const CLEANSE_BURST_SCENE := preload("res://scenes/effects/blight_cleanse_burst.tscn")

## === STATE ===
var _state: State = State.PATROL
var _health: int = 30
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _damage_timer: float = 0.0

## Patrol waypoints: origin (where it spawned) and the far end of its route
var _patrol_origin: Vector3
var _patrol_end: Vector3
var _patrol_target: Vector3

## Player reference, resolved lazily via the "player" group
var _player: Node3D

## Desired movement this frame
var _desired_dir: Vector3 = Vector3.FORWARD
var _target_speed: float = 0.0

## Twitch/bob state
var _time: float = 0.0
var _twitch_timer: float = 0.0
var _twitch_offset: Vector3 = Vector3.ZERO

## Body animation data, captured at ready
var _segments: Array[MeshInstance3D] = []
var _segment_base_y: Array[float] = []
var _segment_base_z: Array[float] = []
var _body_materials: Array[StandardMaterial3D] = []
var _body_base_colors: Array[Color] = []

var _hit_tween: Tween


func _ready() -> void:
	## Enemies live on the blight layer (6). They walk on the environment (2),
	## blighted soil tiles (16), and treat the player (1) as an obstacle.
	collision_layer = 32
	collision_mask = 1 | 2 | 16

	## Damage area only watches for the player
	_damage_area.collision_layer = 0
	_damage_area.collision_mask = 1

	_health = max_health

	## Set up patrol waypoints from spawn position and facing
	_patrol_origin = global_position
	var forward: Vector3 = -global_transform.basis.z
	forward.y = 0.0
	if forward.length() < 0.01:
		forward = Vector3.FORWARD
	_patrol_end = _patrol_origin + forward.normalized() * patrol_distance
	_patrol_target = _patrol_end

	## Collect body segments for the inchworm bob animation
	for child in _visual.get_children():
		if child is MeshInstance3D and child.name.begins_with("Segment"):
			_segments.append(child)
			_segment_base_y.append(child.position.y)
			_segment_base_z.append(child.position.z)

	## Duplicate body materials so hit flashes don't affect every grub instance
	for segment in _segments:
		var mat: Material = segment.get_active_material(0)
		if mat is StandardMaterial3D:
			var dup: StandardMaterial3D = mat.duplicate()
			segment.set_surface_override_material(0, dup)
			_body_materials.append(dup)
			_body_base_colors.append(dup.albedo_color)


func _process(delta: float) -> void:
	if _state == State.DEAD:
		return

	_time += delta

	## Inchworm bob: segments ripple slightly out of phase.
	## Bigger/faster while moving, gentle while idling.
	var speed_ratio: float = Vector3(velocity.x, 0, velocity.z).length() / chase_speed
	var motion: float = 0.4 + clampf(speed_ratio, 0.0, 1.0)
	_visual.position.y = absf(sin(_time * 6.0)) * 0.03 * motion

	for i in _segments.size():
		var phase: float = _time * 5.0 - float(i) * 0.9
		_segments[i].position.y = _segment_base_y[i] + sin(phase) * 0.02 * motion
		_segments[i].position.z = _segment_base_z[i] + cos(phase) * 0.015 * motion

	## Random twitch impulses — the Blight misfiring its stolen nerves
	_twitch_timer -= delta
	if _twitch_timer <= 0.0:
		_twitch_timer = randf_range(1.5, 4.0)
		if _state == State.CHASE:
			_twitch_timer *= 0.4  # Agitated grubs twitch more often
		_twitch_offset = Vector3(
				randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * 0.09
	_twitch_offset = _twitch_offset.lerp(Vector3.ZERO, 6.0 * delta)
	_visual.rotation = _twitch_offset


func _physics_process(delta: float) -> void:
	if _state == State.DEAD:
		return

	## Contact damage cooldown ticks down
	if _damage_timer > 0.0:
		_damage_timer -= delta

	## Stay glued to the ground
	if not is_on_floor():
		velocity.y -= _gravity * 0.7 * delta

	## Resolve the player lazily (survives player respawn/scene changes)
	if _player == null or not is_instance_valid(_player):
		var players := get_tree().get_nodes_in_group("player")
		_player = players[0] if players.size() > 0 else null

	match _state:
		State.PATROL:
			_update_patrol(delta)
		State.CHASE:
			_update_chase(delta)
		State.DEAD:
			pass

	## Sluggish steering — lerp toward desired velocity
	var target_velocity: Vector3 = _desired_dir * _target_speed
	target_velocity.y = velocity.y
	velocity = velocity.lerp(target_velocity, steering_acceleration * delta)

	## Face where we're heading (forward is -Z)
	var flat_vel := Vector3(velocity.x, 0, velocity.z)
	if flat_vel.length() > 0.1:
		var target_yaw: float = atan2(-flat_vel.x, -flat_vel.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, 4.0 * delta)

	move_and_slide()

	## Contact damage: the oversized DamageArea detects the player body.
	## Re-checked every frame with a cooldown so lingering contact keeps hurting.
	if _damage_timer <= 0.0:
		for body in _damage_area.get_overlapping_bodies():
			if body != self and body.has_method("take_damage"):
				body.take_damage(contact_damage, global_position)
				_damage_timer = damage_cooldown
				break

	## Fell off the world (hanging baskets, trellis mispatrol) — cleanup
	if global_position.y < -20.0:
		queue_free()


func _update_patrol(delta: float) -> void:
	## Walk toward the active waypoint; flip when we arrive
	var to_target: Vector3 = _patrol_target - global_position
	to_target.y = 0.0
	if to_target.length() < 0.2:
		_patrol_target = _patrol_origin if _patrol_target == _patrol_end else _patrol_end
		to_target = _patrol_target - global_position
		to_target.y = 0.0

	if to_target.length() > 0.01:
		_desired_dir = to_target.normalized()
	_target_speed = patrol_speed

	## Proximity detection — wake up if the player gets close
	if _player != null:
		var dist: float = global_position.distance_to(_player.global_position)
		if dist < detect_radius:
			_state = State.CHASE
			_agitate()


func _update_chase(delta: float) -> void:
	## Lumbers toward the player; gives up if they escape the lose radius
	if _player == null or not is_instance_valid(_player):
		_state = State.PATROL
		return

	var to_player: Vector3 = _player.global_position - global_position
	var dist: float = to_player.length()
	if dist > lose_radius:
		_state = State.PATROL
		_calm()
		return

	_desired_dir = to_player / dist
	_desired_dir.y = 0.0
	_desired_dir = _desired_dir.normalized()
	_target_speed = chase_speed


func _agitate() -> void:
	## Detection moment: glow flares and the grub shudders
	var tween := create_tween()
	tween.tween_property(_glow_light, "light_energy", 1.6, 0.2)
	_twitch_offset = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * 0.15


func _calm() -> void:
	var tween := create_tween()
	tween.tween_property(_glow_light, "light_energy", 0.6, 0.5)


func take_damage(amount: int) -> void:
	## Called by seed projectiles (see seed_projectile.gd _on_body_entered)
	if _state == State.DEAD:
		return

	_health -= amount
	health_changed.emit(_health, max_health)

	if _health <= 0:
		_die()
	else:
		_hit_flash()


func _hit_flash() -> void:
	## Pain feedback: body flashes pale, visual squashes
	if _hit_tween != null and _hit_tween.is_valid():
		_hit_tween.kill()

	for i in _body_materials.size():
		_body_materials[i].albedo_color = Color(1.0, 0.75, 1.0)

	_hit_tween = create_tween()
	_hit_tween.set_parallel(true)
	for i in _body_materials.size():
		_hit_tween.tween_property(_body_materials[i], "albedo_color",
				_body_base_colors[i], 0.3)
	_hit_tween.set_parallel(false)
	_hit_tween.tween_property(_visual, "scale", Vector3.ONE, 0.2)
	_visual.scale = Vector3(1.15, 0.8, 1.15)


func _die() -> void:
	## Death = a small reclamation: ash chunks + purple sparks + bloom pollen
	_state = State.DEAD

	_damage_area.set_deferred("monitoring", false)
	_collision_shape.set_deferred("disabled", true)
	collision_layer = 0
	_visual.visible = false

	var burst: Node3D = CLEANSE_BURST_SCENE.instantiate()
	get_tree().current_scene.add_child(burst)
	burst.global_position = global_position + Vector3.UP * 0.15

	died.emit(self)

	# Brief linger so the burst has a moment before the body is freed
	await get_tree().create_timer(0.4).timeout
	queue_free()
