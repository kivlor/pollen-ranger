class_name FirstPersonController
extends CharacterBody3D
## First-person player controller for Pollen Ranger
##
## Designed for a "thumb-sized" scout navigating a greenhouse.
## The feel goals are:
## - Floaty, lightweight movement (you're a seed-pod golem)
## - Precise control for platforming between flower pots
## - Satisfying arc when jumping between hanging baskets
##
## Controls:
## - WASD: Movement
## - Shift: Sprint (faster movement)
## - Space: Jump
## - Mouse: Look around
## - Left Click: Fire seed projectile
## - G: Toggle glider

## === MOVEMENT PARAMETERS ===
## Base movement speed (units per second)
## At thumb-scale, this feels like a brisk walk
@export var walk_speed: float = 6.0

## Sprint speed - faster but less precise
@export var sprint_speed: float = 10.0

## How quickly the player accelerates/decelerates
## Higher values = snappier, lower = slipperier
@export var ground_acceleration: float = 12.0
@export var ground_deceleration: float = 16.0
@export var air_acceleration: float = 4.0

## === JUMP PARAMETERS ===
## Initial jump velocity
## Tuned for a floaty arc - you're light like a seed
@export var jump_velocity: float = 5.0

## Gravity multiplier for a "floaty" feel
## Lower than real gravity to give more air control time
@export var gravity_multiplier: float = 0.7

## Coyote time: can still jump briefly after leaving a ledge
## Makes platforming feel forgiving
@export var coyote_time: float = 0.15

## Jump buffer: pressing jump slightly before landing still works
@export var jump_buffer_time: float = 0.1

## === MOUSE LOOK PARAMETERS ===
## Sensitivity is pulled from project settings for user customization
@export var mouse_sensitivity: float = 0.002

## Vertical look limits (in radians)
## Prevents the camera from flipping upside-down
@export var min_pitch: float = -PI/2.2
@export var max_pitch: float = PI/2.2

## === REFERENCES ===
@onready var _camera: Camera3D = $CameraPivot/Camera3D
@onready var _camera_pivot: Node3D = $CameraPivot
@onready var _collision: CollisionShape3D = $CollisionShape3D
@onready var _glider: Node3D = $Glider  # Glider component - use duck typing
@onready var _projectile_spawner: Node3D = $ProjectileSpawner
@onready var _damage_flash: ColorRect = $DamageFeedback/Flash
@onready var _visual_mesh: MeshInstance3D = $MeshInstance3D
@onready var _sfx_hurt: AudioStreamPlayer = $SFX/Hurt
@onready var _sfx_death: AudioStreamPlayer = $SFX/Death
@onready var _sfx_respawn: AudioStreamPlayer = $SFX/Respawn

## Seed-pod burst played when the player dies - the golem comes apart
## into the same pollen/ash reclamation the enemies get.
const DEATH_BURST_SCENE := preload("res://scenes/effects/blight_cleanse_burst.tscn")

## Preload the Glider script for type checking
const GliderScript = preload("res://scripts/glider.gd")

## === HEALTH ===
signal health_changed(current_health: int, max_health: int)
signal player_died

## Hits the player can take before dying (enemies deal 1 contact damage)
@export var max_health: int = 5

## Grace period after taking a hit, prevents multi-tick contact damage
@export var hurt_invulnerability: float = 0.8

## Knockback impulse applied away from the damage source
## Should feel floaty — you're a lightweight seed-pod, you get punted
@export var damage_knockback: float = 3.5
@export var damage_lift: float = 2.0

## === CAMERA SHAKE ===
## Trauma added per point of damage taken. Shake strength is trauma^2,
## so small hits are gentle nudges and the killing blow really rattles.
@export var shake_per_damage: float = 0.45

## How fast trauma decays back to zero (per second)
@export var shake_decay: float = 2.2

## Max angular offset (radians) of the shake at full trauma
@export var shake_max_offset: float = 0.05

## Blink rate (blinks/sec) of the body mesh while invulnerable
@export var iframe_blink_rate: float = 9.0

## Seconds the death dissolve animation runs before the level respawns us.
## The level's RESPAWN_DELAY should be >= this so the effect can read.
@export var death_dissolve_time: float = 0.9

var current_health: int = 5
var _hurt_timer: float = 0.0
var is_dead: bool = false

## Camera-shake state (trauma model: intensity = trauma^2)
var _trauma: float = 0.0
var _shake_time: float = 0.0

## Blink timer for i-frame feedback
var _blink_time: float = 0.0

## === STATE ===
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _time_since_grounded: float = 0.0
var _jump_buffer: float = 0.0
var _mouse_captured: bool = false

## Sprint state
var _is_sprinting: bool = false


func _ready() -> void:
	## Set up collision layer for player
	collision_layer = 1  # Layer 1: player
	collision_mask = 2 | 4 | 8  # Layer 2: environment, 3: climbable, 4: landing

	current_health = max_health
	health_changed.emit(current_health, max_health)
	
	## Capture mouse for first-person controls
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_mouse_captured = true
	
	## Load sensitivity from project settings if available
	var saved_sens = ProjectSettings.get_setting("application/config/mouse_sensitivity")
	if saved_sens != null:
		mouse_sensitivity = saved_sens


func _input(event: InputEvent) -> void:
	## Mouse look - direct camera control feels responsive
	if event is InputEventMouseMotion and _mouse_captured:
		_rotate_camera(event.relative)
	
	## Toggle mouse capture with Escape
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			_toggle_mouse_capture()
		
		## Toggle glider with G
		if event.keycode == KEY_G:
			_toggle_glider()
		
		## Fire seed projectile with left click handled in _physics_process
		## for better frame-accurate spawning


func _physics_process(delta: float) -> void:
	## Update timers
	_update_timers(delta)
	
	## Camera shake always ticks, even while dead (death gets a big shake)
	_update_camera_shake(delta)
	
	## Dead: no input, no shooting - just drift to a stop and let the
	## dissolve animation + level respawn logic take over.
	if is_dead:
		velocity.x = move_toward(velocity.x, 0.0, 8.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 8.0 * delta)
		if not is_on_floor():
			velocity.y -= _gravity * gravity_multiplier * delta
		move_and_slide()
		return
	
	## Check for shooting
	if Input.is_action_just_pressed("shoot"):
		_fire_seed_projectile()
	
	## Handle sprinting
	_is_sprinting = Input.is_key_pressed(KEY_SHIFT)
	
	## Apply gravity with our multiplier for floaty feel
	if not is_on_floor():
		if _glider.is_deployed:
			## Glider overrides normal gravity
			velocity.y = _glider.apply_gravity(velocity.y, delta)
		else:
			velocity.y -= _gravity * gravity_multiplier * delta
	
	## Handle jumping with buffer and coyote time
	_handle_jumping()
	
	## Handle horizontal movement
	_handle_movement(delta)
	
	## Move the character
	move_and_slide()
	
	## Check if we landed - retract glider
	if is_on_floor() and _glider.is_deployed:
		_glider.retract()
	
	## Retract glider if we jumped
	if Input.is_action_just_pressed("jump") and is_on_floor() and _glider.is_deployed:
		_glider.retract()


func _update_timers(delta: float) -> void:
	## Hurt invulnerability cooldown + i-frame blink feedback so the player
	## can SEE they're protected (issue #8: clear feedback)
	if _hurt_timer > 0.0:
		_hurt_timer -= delta
		_blink_time += delta
		_visual_mesh.visible = fmod(_blink_time * iframe_blink_rate, 1.0) < 0.6
		if _hurt_timer <= 0.0:
			_visual_mesh.visible = true
	else:
		_blink_time = 0.0
		_visual_mesh.visible = not is_dead  # hidden during death dissolve

	## Track time since last on ground for coyote time
	if is_on_floor():
		_time_since_grounded = 0.0
	else:
		_time_since_grounded += delta
	
	## Update jump buffer
	if _jump_buffer > 0:
		_jump_buffer -= delta


func _handle_jumping() -> void:
	## Buffer jump input
	if Input.is_action_just_pressed("jump"):
		_jump_buffer = jump_buffer_time
	
	## Execute jump if we have buffer and can jump
	var can_jump: bool = is_on_floor() or _time_since_grounded < coyote_time
	if _jump_buffer > 0 and can_jump and not _glider.is_deployed:
		velocity.y = jump_velocity
		_jump_buffer = 0.0
		_time_since_grounded = coyote_time + 0.01  # Prevent double-jump


func _handle_movement(delta: float) -> void:
	## Get input direction
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	
	## Transform input to world space relative to player facing
	var move_dir := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	## Determine target speed
	var target_speed: float
	if _glider.is_deployed:
		target_speed = _glider.horizontal_speed
	elif _is_sprinting:
		target_speed = sprint_speed
	else:
		target_speed = walk_speed
	
	## Apply acceleration with different rates for ground/air
	var accel: float = ground_acceleration if is_on_floor() else air_acceleration
	if _glider.is_deployed:
		accel = _glider.steering_acceleration
	
	## Calculate target velocity
	var target_velocity := Vector3(move_dir.x * target_speed, velocity.y, move_dir.z * target_speed)
	
	## Interpolate towards target
	velocity = velocity.lerp(target_velocity, accel * delta)


func _rotate_camera(relative: Vector2) -> void:
	## Horizontal rotation (yaw) - rotate entire player body
	rotation.y -= relative.x * mouse_sensitivity
	
	## Vertical rotation (pitch) - only rotate camera pivot
	_camera_pivot.rotation.x -= relative.y * mouse_sensitivity
	_camera_pivot.rotation.x = clamp(_camera_pivot.rotation.x, min_pitch, max_pitch)


func _toggle_mouse_capture() -> void:
	if _mouse_captured:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_mouse_captured = false
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_mouse_captured = true


func _toggle_glider() -> void:
	## Can only toggle glider when not on ground (or to retract)
	if not is_on_floor() or _glider.is_deployed:
		_glider.toggle()


func _fire_seed_projectile() -> void:
	## Spawn position is slightly in front and below camera
	## This simulates shooting from an "arm cannon"
	var spawn_pos: Vector3 = _projectile_spawner.global_position
	var spawn_dir: Vector3 = -_camera_pivot.global_basis.z
	
	## Create the seed projectile
	var seed_scene: PackedScene = preload("res://scenes/player/seed_projectile.tscn")
	var seed: Node3D = seed_scene.instantiate()
	
	## Add to scene tree
	get_tree().current_scene.add_child(seed)
	
	## Initialize position and direction
	seed.global_position = spawn_pos
	seed.initialize(spawn_dir, _camera.global_basis)
	
	## Optional: play shoot sound or visual feedback


## Restore full health (used by level respawn logic)
func heal_to_full() -> void:
	current_health = max_health
	is_dead = false
	health_changed.emit(current_health, max_health)


## Respawn at a position: restore health, zero velocity, teleport.
## Used by levels with checkpoints / kill planes (Entrance Conservatory).
func respawn_at(new_position: Vector3) -> void:
	heal_to_full()
	velocity = Vector3.ZERO
	global_position = new_position
	## Retract the glider so a mid-air death doesn't respawn us floating
	if _glider.is_deployed:
		_glider.retract()
	
	## Bring the body back from the dissolve
	_visual_mesh.visible = true
	_visual_mesh.scale = Vector3.ONE
	
	## Brief i-frames after respawn so a lingering enemy can't instantly
	## re-kill you — punishing but fair (issue #8)
	_hurt_timer = hurt_invulnerability
	_sfx_respawn.play()


## Public accessor for camera (useful for UI, cutscenes, etc.)
func get_camera() -> Camera3D:
	return _camera


## Check if player is grounded (with small tolerance)
func is_grounded() -> bool:
	return is_on_floor() or _time_since_grounded < coyote_time


## Get current movement speed for UI/debug
func get_current_speed() -> float:
	return Vector3(velocity.x, 0, velocity.z).length()


## Take damage from enemies/hazards. Called by enemy contact damage and
## (in future) hazard scripts. The source position drives the knockback arc.
func take_damage(amount: int, from_position: Vector3 = Vector3.ZERO) -> void:
	if is_dead or _hurt_timer > 0.0:
		return
	_hurt_timer = hurt_invulnerability

	current_health = maxi(current_health - amount, 0)
	health_changed.emit(current_health, max_health)

	## Knockback: punt the player away from the source with a floaty lift
	var away: Vector3 = global_position - from_position
	away.y = 0.0
	if away.length() < 0.01:
		away = -global_transform.basis.z
	velocity += away.normalized() * damage_knockback + Vector3.UP * damage_lift

	_flash_damage()
	add_trauma(shake_per_damage * amount)
	_sfx_hurt.play()

	if current_health <= 0:
		_die()


func _die() -> void:
	## Death state: input dies first, then the body dissolves into pollen
	## (seed-pod golems come apart the same way blighted things do).
	is_dead = true
	_hurt_timer = 0.0  # stop the i-frame blink so the dissolve reads cleanly
	player_died.emit()

	## Big shake + kill the flash so the dissolve reads cleanly
	add_trauma(1.0)
	if _glider.is_deployed:
		_glider.retract()

	## Dissolve: the body shrinks away as if un-raveling into seeds.
	## The mesh is hidden while dead (see _update_timers); the tween shapes
	## the visible shrink before it disappears.
	_sfx_death.play()
	var dissolve := create_tween()
	dissolve.tween_property(_visual_mesh, "scale", Vector3.ONE * 0.05, \
			death_dissolve_time).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)

	## Pollen burst at the chest, matching enemy death reclamation feel
	var burst: Node3D = DEATH_BURST_SCENE.instantiate()
	get_tree().current_scene.add_child(burst)
	burst.global_position = global_position + Vector3.UP * 0.3


func add_trauma(amount: float) -> void:
	## Add camera shake trauma (clamped 0..1). Intensity is trauma^2 so
	## light hits nudge and heavy hits rattle.
	_trauma = clampf(_trauma + amount, 0.0, 1.0)


func _update_camera_shake(delta: float) -> void:
	## Trauma decays linearly; shake offsets are layered sines of different
	## frequencies so the shake feels organic rather than a flat rattle.
	_trauma = maxf(_trauma - shake_decay * delta, 0.0)
	var shake: float = _trauma * _trauma
	if _camera == null:
		return
	if shake <= 0.0001:
		_camera.rotation = Vector3.ZERO
		return
	_shake_time += delta
	_camera.rotation = Vector3(
			sin(_shake_time * 31.0) * 0.5 + sin(_shake_time * 17.3) * 0.5,
			sin(_shake_time * 24.7) * 0.5 + sin(_shake_time * 41.0) * 0.5,
			sin(_shake_time * 37.0)) * shake_max_offset * shake


func _flash_damage() -> void:
	## Visual feedback: red vignette flash + small camera roll punch
	_damage_flash.color.a = 0.45
	var tween := create_tween()
	tween.tween_property(_damage_flash, "color:a", 0.0, 0.4).set_ease(Tween.EASE_OUT)

	_camera_pivot.rotation.z = 0.08
	var roll_tween := create_tween()
	roll_tween.tween_property(_camera_pivot, "rotation:z", 0.0, 0.3) \
			.set_ease(Tween.EASE_OUT)
