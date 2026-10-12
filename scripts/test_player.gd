class_name TestPlayer
extends CharacterBody3D
## Simple first-person test player for prop testing
## Supports walking, jumping, climbing trellis, and gliding to baskets

## Movement speed
@export var walk_speed: float = 5.0
@export var sprint_speed: float = 8.0
@export var jump_velocity: float = 4.5

## Gravity from project settings
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

## Climbing state
var _is_climbing: bool = false
var _climb_speed: float = 2.0
var _current_trellis: TrellisLadder = null

## Gliding state
var _is_glider_deployed: bool = false
var _glider_fall_speed: float = 2.0  # Slow fall when gliding
var _glider_horizontal_speed: float = 6.0
var _glider_turn_speed: float = 2.0

@onready var _camera: Camera3D = $Camera3D
@onready var _collision: CollisionShape3D = $CollisionShape3D

var _mouse_captured: bool = false


func _ready() -> void:
	add_to_group("player")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_mouse_captured = true


func _input(event: InputEvent) -> void:
	# Mouse look
	if event is InputEventMouseMotion and _mouse_captured:
		rotation.y -= event.relative.x * 0.002
		_camera.rotation.x -= event.relative.y * 0.002
		_camera.rotation.x = clamp(_camera.rotation.x, -PI/2.5, PI/2.5)
	
	# Toggle mouse capture
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			if _mouse_captured:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
				_mouse_captured = false
			else:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
				_mouse_captured = true
		
		# Deploy/retract glider
		if event.keycode == KEY_G:
			_toggle_glider()


func _physics_process(delta: float) -> void:
	# Handle climbing
	if _is_climbing:
		_handle_climbing(delta)
		return
	
	# Add gravity
	if not is_on_floor():
		if _is_glider_deployed:
			# Glider physics: slow fall with horizontal movement
			velocity.y = max(velocity.y - _gravity * delta * 0.1, -_glider_fall_speed)
		else:
			velocity.y -= _gravity * delta
	
	# Handle jump
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity
		_is_glider_deployed = false  # Retract glider when jumping
	
	# Get movement input
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	# Apply movement
	var speed := sprint_speed if Input.is_action_pressed("aim_down_sights") else walk_speed
	if _is_glider_deployed:
		speed = _glider_horizontal_speed
	
	if direction:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)
	
	move_and_slide()


func _handle_climbing(delta: float) -> void:
	# Get climb input
	var climb_input := Input.get_axis("move_back", "move_forward")
	
	# Apply climbing velocity
	velocity.y = climb_input * _climb_speed
	
	# Allow some horizontal movement while climbing
	var horiz_input := Input.get_vector("move_left", "move_right", 0, 0)
	velocity.x = horiz_input.x * walk_speed * 0.3
	velocity.z = 0
	
	move_and_slide()
	
	# Exit climbing when jumping or at top/bottom
	if Input.is_action_just_pressed("jump"):
		_exit_climb()
		velocity.y = jump_velocity  # Jump off the ladder
	
	# Check if still in range of trellis
	if _current_trellis and not _current_trellis.can_climb():
		_exit_climb()


func _toggle_glider() -> void:
	_is_glider_deployed = not _is_glider_deployed
	# Visual feedback would go here (show/hide dandelion fluff parachute)


func _enter_climb(trellis: TrellisLadder) -> void:
	if _is_climbing:
		return
	
	_is_climbing = true
	_current_trellis = trellis
	velocity.y = 0
	# Could play climb animation here


func _exit_climb() -> void:
	_is_climbing = false
	_current_trellis = null


func on_trellis_entered(trellis: TrellisLadder) -> void:
	# Player can start climbing when touching trellis
	_current_trellis = trellis
	if Input.is_action_pressed("move_forward"):
		_enter_climb(trellis)


func on_trellis_exited(_trellis: TrellisLadder) -> void:
	if _is_climbing and _current_trellis == _trellis:
		_exit_climb()
	_current_trellis = null


func on_basket_landed(basket: HangingBasket) -> void:
	# Basket will sway more when player lands
	print("Landed on basket: ", basket.name)


func on_basket_left(_basket: HangingBasket) -> void:
	pass
