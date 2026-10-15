class_name BlightedMoth
extends CharacterBody3D
## Blighted Moth — the greenhouse's aerial tier of corrupted wildlife.
##
## A moth with a ~1.5 m wingspan (huge from the thumb-sized player's
## perspective), consumed by The Blight: tattered gray wings trailing
## glowing purple blight motes and a constant dust of wing-scales.
##
## Behavior:
## - Lazy figure-8 flutter at medium height around its spawn anchor
## - Cone-of-vision detection with line-of-sight check; a GLIDING player
##   is spotted from much further away (an exposed fluff-parachute is
##   irresistible to a moth that thinks everything is a light)
## - Swoop attack: telegraphed wind-up -> fast dive at (a lead of) the
##   player -> recovery climb -> return to the patrol path
## - Contact damage via an oversized Area3D (brushing a wing hurts)
## - Dies when hit by seed projectiles — including shots fired while
##   the player is gliding alongside it
##
## Feel goals (DESIGN.md):
## - Erratic, twitchy flight — like a moth near a light, never smooth
## - The dive should startle: a flare of blight light, a burst of speed
## - Death is a tiny reclamation: ash + purple sparks + bloom pollen

signal health_changed(current_health: int, max_health: int)
signal died(moth: BlightedMoth)

enum State { PATROL, WINDUP, SWOOP, RECOVER, RETURN, DEAD }

## === COMBAT ===
## Health — one seed hit kills (seed projectile deals 10).
## Moths are fragile; the challenge is hitting an erratic aerial target.
@export var max_health: int = 10

## Damage dealt to the player on contact (swoop impacts included)
@export var contact_damage: int = 1

## Seconds between contact damage ticks while touching the player
@export var damage_cooldown: float = 1.2

## === PATROL (figure-8) ===
## Height above the spawn anchor the moth patrols at
@export var patrol_height: float = 2.0

## Half-width of the figure-8 along the moth's patrol axis
@export var patrol_radius_x: float = 2.2

## Half-width of the figure-8 across it (the crossing loops)
@export var patrol_radius_z: float = 1.4

## How fast the moth travels its figure-8 — lazy, drifting
@export var patrol_speed: float = 1.8

## Vertical flutter bob layered onto the patrol path
@export var flutter_amplitude: float = 0.3

## Frequency of the flutter bob (kept low; the wing-flap is separate)
@export var flutter_frequency: float = 0.9

## === DETECTION (cone of vision) ===
## Range at which the moth notices a grounded player
@export var detect_range: float = 8.0

## Multiplier applied to detect_range when the player is GLIDING.
## A dangling dandelion-parachute reads as "light" to a blighted moth.
@export var glide_detect_multiplier: float = 1.75

## Full angle of the vision cone (degrees). The moth must roughly face
## the player to spot them — sneaking up from behind works. Wide, because
## a twitchy compound-eyed moth notices motion all around its heading.
@export var vision_cone_degrees: float = 100.0

## Inside this radius the moth senses the player regardless of facing —
## fluttering wings feel nearby movement, like a moth drawn to a light.
@export var close_sense_radius: float = 2.5

## === SWOOP ===
## Dive speed — much faster than patrol; the swoop should startle
@export var swoop_speed: float = 7.5

## Hover-and-flare time before committing to the dive (telegraph)
@export var swoop_windup_time: float = 0.35

## Longest a single dive may run before the moth gives up and recovers
@export var swoop_max_time: float = 1.6

## How far ahead of the player's current position the moth aims
## (seconds of player velocity — leads moving targets slightly)
@export var swoop_lead_time: float = 0.12

## Seconds the moth must patrol calmly between swoops
@export var swoop_cooldown: float = 3.0

## Speed while climbing away and flying back to the patrol path
@export var return_speed: float = 2.6

## === MOVEMENT ===
## How fast the moth steers toward its desired velocity
## Low values keep the flight drifting and moth-like
@export var steering_acceleration: float = 4.0

## === REFERENCES ===
@onready var _visual: Node3D = $Visual
@onready var _collision_shape: CollisionShape3D = $CollisionShape3D
@onready var _damage_area: Area3D = $DamageArea
@onready var _glow_light: OmniLight3D = $Visual/GlowLight
@onready var _wing_l_pivot: Node3D = $Visual/WingLPivot
@onready var _wing_r_pivot: Node3D = $Visual/WingRPivot
@onready var _blight_trail: GPUParticles3D = $BlightTrail

## Reusable cleanse burst — moth death is a tiny "reclamation" moment
const CLEANSE_BURST_SCENE := preload("res://scenes/effects/blight_cleanse_burst.tscn")

## === STATE ===
var _state: State = State.PATROL
var _health: int = 10
var _damage_timer: float = 0.0
var _swoop_cooldown_timer: float = 0.0

## Patrol anchor: spawn position + patrol height. The figure-8 is drawn
## around this point, so the moth always returns to where it belonged.
var _anchor: Vector3

## Phase along the figure-8 curve
var _patrol_time: float = 0.0

## Player reference, resolved lazily via the "player" group
var _player: Node3D

## Desired movement this frame
var _desired_dir: Vector3 = Vector3.FORWARD
var _target_speed: float = 0.0

## Swoop bookkeeping
var _swoop_target: Vector3
var _swoop_timer: float = 0.0

## Wing-flap / twitch state
var _time: float = 0.0
var _flap_speed: float = 18.0
var _jitter_timer: float = 0.0
var _jitter: Vector3 = Vector3.ZERO
var _twitch_timer: float = 0.0
var _twitch_offset: Vector3 = Vector3.ZERO

## Wing and body materials, duplicated so hit flashes stay per-instance
var _wing_materials: Array[StandardMaterial3D] = []
var _wing_base_colors: Array[Color] = []

var _hit_tween: Tween


func _ready() -> void:
	## Enemies live on the blight layer (32). The moth flies, so it only
	## needs to avoid the environment (2) and blighted soil tiles (16);
	## the player (1) is handled by the DamageArea, not solid collision.
	collision_layer = 32
	collision_mask = 2 | 16

	## Damage area only watches for the player
	_damage_area.collision_layer = 0
	_damage_area.collision_mask = 1

	_health = max_health

	## The figure-8 is anchored to the spawn point, lifted to patrol height
	_anchor = global_position + Vector3.UP * patrol_height

	## Duplicate wing materials so hit flashes don't affect every moth
	for wing_mesh: MeshInstance3D in [_wing_l_pivot.get_node("WingL"), _wing_r_pivot.get_node("WingR")]:
		var mat: Material = wing_mesh.get_active_material(0)
		if mat is StandardMaterial3D:
			var dup: StandardMaterial3D = mat.duplicate()
			wing_mesh.set_surface_override_material(0, dup)
			_wing_materials.append(dup)
			_wing_base_colors.append(dup.albedo_color)


func _process(delta: float) -> void:
	if _state == State.DEAD:
		return

	_time += delta

	## Wing-flap: fast and frantic. The flap rate rises when the moth is
	## agitated (wind-up/swoop), which reads as panic from the ground.
	var agitated: bool = _state == State.WINDUP or _state == State.SWOOP
	var target_flap_speed: float = 26.0 if agitated else 18.0
	_flap_speed = lerpf(_flap_speed, target_flap_speed, 6.0 * delta)

	var flap_phase: float = _time * _flap_speed
	var flap_amplitude: float = 1.1 if agitated else 0.8
	_wing_l_pivot.rotation.z = sin(flap_phase) * flap_amplitude
	_wing_r_pivot.rotation.z = -sin(flap_phase) * flap_amplitude

	## Fast body-bounce driven by the wing-beat (visual only)
	_visual.position.y = sin(flap_phase * 0.5) * 0.02

	## Random twitch impulses — the Blight misfiring its stolen nerves.
	## Moths are MORE twitchy while patrolling calm; the swoop is focused.
	_twitch_timer -= delta
	if _twitch_timer <= 0.0:
		_twitch_timer = randf_range(0.4, 1.4) if agitated else randf_range(0.6, 1.8)
		_twitch_offset = Vector3(
				randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * 0.12
	_twitch_offset = _twitch_offset.lerp(Vector3.ZERO, 6.0 * delta)
	_visual.rotation = _twitch_offset


func _physics_process(delta: float) -> void:
	if _state == State.DEAD:
		return

	## Contact damage cooldown ticks down
	if _damage_timer > 0.0:
		_damage_timer -= delta

	if _swoop_cooldown_timer > 0.0:
		_swoop_cooldown_timer -= delta

	## Resolve the player lazily (survives player respawn/scene changes)
	if _player == null or not is_instance_valid(_player):
		var players := get_tree().get_nodes_in_group("player")
		_player = players[0] if players.size() > 0 else null

	## Random velocity jitter — flight should never be a clean straight line
	_jitter_timer -= delta
	if _jitter_timer <= 0.0:
		_jitter_timer = randf_range(0.2, 0.5)
		_jitter = Vector3(
				randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0))

	match _state:
		State.PATROL:
			_update_patrol(delta)
		State.WINDUP:
			_update_windup(delta)
		State.SWOOP:
			_update_swoop(delta)
		State.RECOVER:
			_update_recover(delta)
		State.RETURN:
			_update_return(delta)
		State.DEAD:
			pass

	## Steering: drift toward the desired velocity (moth-like mushiness)
	var target_velocity: Vector3 = _desired_dir * _target_speed
	velocity = velocity.lerp(target_velocity, steering_acceleration * delta)

	## Face where we're heading (forward is -Z), banking into turns
	var flat_vel := Vector3(velocity.x, 0, velocity.z)
	if flat_vel.length() > 0.2:
		var target_yaw: float = atan2(-flat_vel.x, -flat_vel.z)
		var yaw_delta: float = wrapf(target_yaw - rotation.y, -PI, PI)
		rotation.y = lerp_angle(rotation.y, target_yaw, 5.0 * delta)
		rotation.z = lerpf(rotation.z,
				clampf(yaw_delta * 0.6, -0.35, 0.35), 4.0 * delta)
	else:
		rotation.z = lerpf(rotation.z, 0.0, 4.0 * delta)

	move_and_slide()

	## Contact damage: the oversized DamageArea detects the player body.
	## Re-checked every frame with a cooldown so lingering contact keeps hurting.
	if _damage_timer <= 0.0:
		for body in _damage_area.get_overlapping_bodies():
			if body != self and body.has_method("take_damage"):
				body.take_damage(contact_damage, global_position)
				_damage_timer = damage_cooldown
				break

	## Fell off the world — cleanup
	if global_position.y < -20.0:
		queue_free()


func _figure8_point() -> Vector3:
	## Lemniscate of Gerono: x = a·cos(t), z = b·sin(t)·cos(t).
	## Crosses itself at the anchor — a lazy lying-down figure-8.
	var t := _patrol_time
	return _anchor + Vector3(
			cos(t) * patrol_radius_x,
			sin(t * flutter_frequency * TAU) * flutter_amplitude,
			sin(t) * cos(t) * patrol_radius_z * 2.0)


func _update_patrol(delta: float) -> void:
	## Advance along the figure-8 and steer toward the next point on it
	_patrol_time += delta * patrol_speed * 0.35
	var target := _figure8_point()
	var to_target := target - global_position
	_desired_dir = to_target.normalized()
	_target_speed = patrol_speed
	_desired_dir += _jitter * 0.25  # erratic drift on top of the path

	## Cone-of-vision detection; a gliding player is spotted much further off
	if _swoop_cooldown_timer <= 0.0 and _can_see_player():
		_swoop_cooldown_timer = swoop_cooldown
		_state = State.WINDUP
		_swoop_timer = swoop_windup_time
		_agitate()


func _update_windup(delta: float) -> void:
	## Telegraph: hover in place, flare, keep glaring at the player
	_swoop_timer -= delta
	_target_speed = 0.6  # near-hover, still twitching
	if _player != null and is_instance_valid(_player):
		_desired_dir = (_player.global_position - global_position).normalized() * 0.2

		if _swoop_timer <= 0.0:
			## Commit to the dive: aim at where the player WILL be
			_swoop_target = _player.global_position \
					+ _player.velocity * swoop_lead_time
			_state = State.SWOOP
			_swoop_timer = swoop_max_time
	else:
		_state = State.RECOVER


func _update_swoop(delta: float) -> void:
	## Fast committed dive at the captured target point
	_swoop_timer -= delta
	var to_target := _swoop_target - global_position
	if to_target.length() < 0.5 or _swoop_timer <= 0.0:
		_state = State.RECOVER
		return

	_desired_dir = to_target.normalized() + _jitter * 0.1
	_target_speed = swoop_speed

	## If the player vanishes mid-dive, bail out to recovery
	if _player == null or not is_instance_valid(_player):
		_state = State.RECOVER


func _update_recover(delta: float) -> void:
	## Climb away for a moment, then hand over to the return flight
	_desired_dir = (Vector3.UP * 1.4 - global_transform.basis.z * 0.6).normalized()
	_target_speed = return_speed
	if global_position.y >= _anchor.y - 0.4:
		_state = State.RETURN
		_calm()


func _update_return(delta: float) -> void:
	## Fly back onto the figure-8 path; PATROL resumes once close to it
	var target := _figure8_point()
	var to_target := target - global_position
	if to_target.length() < 0.6:
		_state = State.PATROL
		return

	_desired_dir = to_target.normalized()
	_target_speed = return_speed


func _can_see_player() -> bool:
	## Cone of vision + line of sight. Returns true when the moth should
	## start a swoop.
	if _player == null or not is_instance_valid(_player):
		return false

	var to_player: Vector3 = _player.global_position - global_position
	var dist: float = to_player.length()
	if dist < 0.01:
		return true

	## Gliding players hang exposed in the air — the moth notices them
	## from much further away, like a light in the dark.
	var range_limit: float = detect_range
	var glider: Node = _player.get_node_or_null("Glider")
	if glider != null and "is_deployed" in glider and glider.is_deployed:
		range_limit *= glide_detect_multiplier

	if dist > range_limit:
		return false

	## Cone check: the direction to the player must fall inside the
	## vision cone around the moth's facing (forward is -Z) — unless the
	## player is close enough that the moth senses them directly.
	if dist > close_sense_radius:
		var forward: Vector3 = -global_transform.basis.z
		if forward.dot(to_player / dist) < cos(deg_to_rad(vision_cone_degrees * 0.5)):
			return false

	## Line of sight: environment/soil between moth and player blocks vision
	var ray_end: Vector3 = _player.global_position + Vector3.UP * 0.3
	var params := PhysicsRayQueryParameters3D.create(
			global_position, ray_end, 2 | 16, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(params)
	if not hit.is_empty() \
			and global_position.distance_to(hit.position) < dist - 0.4:
		return false

	return true


func _agitate() -> void:
	## Detection moment: glow flares, trail brightens, wings go frantic
	var tween := create_tween()
	tween.tween_property(_glow_light, "light_energy", 1.8, 0.2)
	_blight_trail.amount_ratio = 1.0
	_twitch_offset = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * 0.2


func _calm() -> void:
	## Back to lazy patrol visuals
	var tween := create_tween()
	tween.tween_property(_glow_light, "light_energy", 0.7, 0.5)
	_blight_trail.amount_ratio = 0.5


func take_damage(amount: int) -> void:
	## Called by seed projectiles (see seed_projectile.gd _on_body_entered).
	## Works from the ground or mid-glide — the moth is always vulnerable.
	if _state == State.DEAD:
		return

	_health -= amount
	health_changed.emit(_health, max_health)

	if _health <= 0:
		_die()
	else:
		_hit_flash()


func _hit_flash() -> void:
	## Pain feedback: wings flash pale, body squashes
	if _hit_tween != null and _hit_tween.is_valid():
		_hit_tween.kill()

	for i in _wing_materials.size():
		_wing_materials[i].albedo_color = Color(1.0, 0.75, 1.0)

	_hit_tween = create_tween()
	_hit_tween.set_parallel(true)
	for i in _wing_materials.size():
		_hit_tween.tween_property(_wing_materials[i], "albedo_color",
				_wing_base_colors[i], 0.3)
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
	_blight_trail.emitting = false

	var burst: Node3D = CLEANSE_BURST_SCENE.instantiate()
	get_tree().current_scene.add_child(burst)
	burst.global_position = global_position

	died.emit(self)

	# Brief linger so the burst has a moment before the body is freed
	await get_tree().create_timer(0.4).timeout
	queue_free()
