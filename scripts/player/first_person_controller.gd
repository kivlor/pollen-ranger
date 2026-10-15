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

var current_health: int = 5
var _hurt_timer: float = 0.0

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
	## Hurt invulnerability cooldown
	if _hurt_timer > 0.0:
		_hurt_timer -= delta

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
	if _hurt_timer > 0.0:
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

	if current_health <= 0:
		player_died.emit()


func _flash_damage() -> void:
	## Visual feedback: red vignette flash + small camera roll punch
	_damage_flash.color.a = 0.45
	var tween := create_tween()
	tween.tween_property(_damage_flash, "color:a", 0.0, 0.4).set_ease(Tween.EASE_OUT)

	_camera_pivot.rotation.z = 0.08
	var roll_tween := create_tween()
	roll_tween.tween_property(_camera_pivot, "rotation:z", 0.0, 0.3) \
			.set_ease(Tween.EASE_OUT)
