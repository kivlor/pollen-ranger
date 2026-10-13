class_name Glider
extends Node3D
## Dandelion glider component for Pollen Ranger
##
## Deployable parachute that slows fall and allows steering.
## The feel goals are:
## - Floaty, gentle descent (like a dandelion seed)
## - Responsive steering without being twitchy
## - Visual satisfaction when deploying (fluff unfurls)
##
## Controls while deployed:
## - WASD: Steer left/right/forward/back
## - Mouse: Look around (doesn't affect direction directly)
## - G or landing: Retract

## === GLIDE PARAMETERS ===
## Terminal velocity while gliding - slow, gentle descent
@export var fall_speed: float = 2.0

## Horizontal movement speed while gliding
## Slightly faster than walking to make gliding rewarding
@export var horizontal_speed: float = 8.0

## How quickly the glider responds to steering input
@export var steering_acceleration: float = 5.0

## Tilt amount when steering (visual feedback)
@export var max_tilt: float = 0.3

## === DEPLOYMENT ===
## Minimum fall time before can deploy (prevents instant deploy)
@export var min_fall_time: float = 0.1

## === REFERENCES ===
@onready var _glider_mesh: Node3D = $GliderMesh  # Visual representation

## === STATE ===
var is_deployed: bool = false
var _deploy_time: float = 0.0
var _target_tilt: Vector3 = Vector3.ZERO


func _ready() -> void:
	## Start hidden
	if _glider_mesh:
		_glider_mesh.visible = false


func _process(delta: float) -> void:
	if not is_deployed:
		return
	
	## Update visual tilt based on movement
	_update_visuals(delta)


## Apply gravity modification while gliding
## Returns the modified Y velocity
func apply_gravity(current_y_velocity: float, delta: float) -> float:
	## Gradually slow to terminal fall speed
	## This creates a satisfying "catch" when deploying mid-fall
	var target_y: float = -fall_speed
	
	## Smooth interpolation for nice feel
	return lerpf(current_y_velocity, target_y, 2.0 * delta)


## Toggle glider deployment
func toggle() -> void:
	if is_deployed:
		retract()
	else:
		deploy()


## Deploy the glider
func deploy() -> void:
	if is_deployed:
		return
	
	is_deployed = true
	_deploy_time = Time.get_ticks_msec() / 1000.0
	
	## Show the glider mesh with animation
	if _glider_mesh:
		_glider_mesh.visible = true
		_animate_deploy()
	
	## Could play deploy sound here
	# $DeploySound.play()


## Retract the glider
func retract() -> void:
	if not is_deployed:
		return
	
	is_deployed = false
	
	## Hide the glider mesh with animation
	if _glider_mesh:
		_animate_retract()
		# Delay hiding until animation finishes
		await get_tree().create_timer(0.2).timeout
		if not is_deployed:  # Check again in case redeployed
			_glider_mesh.visible = false
	
	## Reset tilt
	_target_tilt = Vector3.ZERO


func _update_visuals(delta: float) -> void:
	if not _glider_mesh:
		return
	
	## Calculate tilt based on parent's velocity
	var parent := get_parent() as CharacterBody3D
	if not parent:
		return
	
	## Tilt in the direction of movement
	var horiz_velocity := Vector2(parent.velocity.x, parent.velocity.z)
	var speed_ratio: float = clamp(horiz_velocity.length() / horizontal_speed, 0.0, 1.0)
	
	## Get movement direction for tilt
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	_target_tilt = Vector3(-input_dir.y * max_tilt, 0.0, -input_dir.x * max_tilt) * speed_ratio
	
	## Smoothly interpolate to target tilt
	_glider_mesh.rotation.x = lerpf(_glider_mesh.rotation.x, _target_tilt.x, steering_acceleration * delta)
	_glider_mesh.rotation.z = lerpf(_glider_mesh.rotation.z, _target_tilt.z, steering_acceleration * delta)


func _animate_deploy() -> void:
	## Play deployment animation
	## In production, this would be an AnimationPlayer or tween
	if not _glider_mesh:
		return
	
	## Scale from 0 to 1 with bounce effect
	_glider_mesh.scale = Vector3(0.01, 0.01, 0.01)
	
	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_ELASTIC)
	tween.tween_property(_glider_mesh, "scale", Vector3(1.0, 1.0, 1.0), 0.3)


func _animate_retract() -> void:
	## Play retraction animation
	if not _glider_mesh:
		return
	
	var tween := create_tween()
	tween.set_ease(Tween.EASE_IN)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(_glider_mesh, "scale", Vector3(0.01, 0.01, 0.01), 0.15)
