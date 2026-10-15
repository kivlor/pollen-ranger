class_name SeedProjectile
extends RigidBody3D
## Seed projectile for Pollen Ranger's arm-cannon
##
## Physics-based projectile that simulates a seed capsule fired from the player.
## The feel goals are:
## - Fast travel but still visible (like a thrown seed pod)
## - Slight arc from gravity (skill shots at distance)
## - Satisfying impact with particle burst
##
## Seeds despawn after max_range or max_lifetime for performance.

## === PROJECTILE PARAMETERS ===
## Initial velocity when fired
@export var launch_speed: float = 25.0

## Gravity effect - lower than normal for flatter trajectory
## Note: Using RigidBody3D's built-in gravity_scale property
## @export var gravity_scale: float = 0.5  # Already defined in RigidBody3D

## Linear drag for slight slowdown over distance
@export var linear_drag: float = 0.3

## Maximum range before despawning
@export var max_range: float = 50.0

## Maximum lifetime in seconds (safety despawn)
@export var max_lifetime: float = 5.0

## Damage dealt to blight on impact
@export var damage: int = 10

## === VISUAL PARAMETERS ===
## Size of the seed capsule (tiny - you're thumb-sized!)
@export var seed_size: float = 0.05

## Trail length for visibility
@export var trail_length: int = 8

## === REFERENCES ===
@onready var _mesh: MeshInstance3D = $MeshInstance3D

## === STATE ===
var _start_position: Vector3
var _lifetime: float = 0.0
var _is_initialized: bool = false
var _trail_points: Array[Vector3] = []


func _ready() -> void:
	## Set up collision
	collision_layer = 32
	## Mask environment (2), blighted soil tiles (16) and blight enemies (32)
	## so seeds can purify soil AND damage creatures like the Blighted Grub
	collision_mask = 2 | 16 | 32
	
	## Configure physics
	gravity_scale = gravity_scale
	linear_damp = linear_drag

	## body_entered only fires when contact monitoring is enabled
	## (a RigidBody3D default-off setting — without this, impacts are never detected)
	contact_monitor = true
	max_contacts_reported = 4
	
	## Connect to collision
	body_entered.connect(_on_body_entered)
	
	## Store start position for range check
	_start_position = global_position


func _physics_process(delta: float) -> void:
	if not _is_initialized:
		return
	
	## Update lifetime
	_lifetime += delta
	if _lifetime > max_lifetime:
		_despawn()
		return
	
	## Check range
	var distance_traveled: float = global_position.distance_to(_start_position)
	if distance_traveled > max_range:
		_despawn()
		return
	
	## Update trail
	_update_trail()


## Initialize the projectile with a direction and optional orientation
func initialize(direction: Vector3, basis: Basis = Basis()) -> void:
	## Set velocity
	linear_velocity = direction.normalized() * launch_speed
	
	## Orient the seed to face the direction of travel
	#look_at(global_position + direction, Vector3.UP)
	
	_is_initialized = true


func _update_trail() -> void:
	## Add current position to trail
	_trail_points.append(global_position)
	
	## Limit trail length
	while _trail_points.size() > trail_length:
		_trail_points.remove_at(0)
	
	## Update trail visualization
	## (In production, this would update a LineEdit or particle system)
	# _trail.update_points(_trail_points)
	pass


func _on_body_entered(body: Node) -> void:
	## Don't hit ourselves (player)
	if body.is_in_group("player"):
		return
	
	## Spawn impact effect
	_spawn_impact_particles()
	
	## Handle different collision types
	if body.has_method("take_damage"):
		## Hit an enemy (blight)
		body.take_damage(damage)
	elif _try_cleanse_soil(body):
		## Hit a soil grid tile - cleanse it
		pass
	elif _try_cleanse_blight_surface(body):
		## Hit a blighted prop - purify it (satisfying burst!)
		pass
	elif body.is_in_group("environment"):
		## Hit environment - play subtle impact
		pass
	
	## Despawn the seed
	_despawn()


func _try_cleanse_soil(body: Node) -> bool:
	"""Try to find a soil grid and cleanse the tile. Returns true if successful."""
	## Check if this body is part of a soil grid tile
	var grid_pos: Variant = null
	var soil_grid: SoilGrid = null
	
	# Body might have grid_pos set directly (SoilTileBody)
	if "grid_pos" in body:
		grid_pos = body.grid_pos
	
	# Find the SoilGrid ancestor
	var ancestor: Node = body
	while ancestor:
		if ancestor is SoilGrid:
			soil_grid = ancestor
			break
		ancestor = ancestor.get_parent()
	
	# If we found both, cleanse the tile
	if soil_grid and grid_pos != null:
		var pos: Vector2i = grid_pos
		if soil_grid.get_tile_state(pos) == SoilGrid.TileState.BLIGHT:
			soil_grid.cleanse_tile(pos)
			return true
	
	return false


func _try_cleanse_blight_surface(body: Node) -> bool:
	"""Try to find a BlightSurface on the hit prop and purge it."""
	var ancestor: Node = body
	while ancestor:
		for child in ancestor.get_children():
			if child is BlightSurface and child.is_blighted():
				child.cleanse()
				return true
		ancestor = ancestor.get_parent()
	return false


func _spawn_impact_particles() -> void:
	## Create impact particle burst
	## In production, this would instantiate a particle scene
	## For now, create a simple expanding sphere effect
	
	var impact_scene: PackedScene = preload("res://scenes/player/seed_impact.tscn")
	if impact_scene:
		var impact: Node3D = impact_scene.instantiate()
		get_tree().current_scene.add_child(impact)
		impact.global_position = global_position
	
	## Alternative: Simple GPUParticles3D inline
	# var particles := GPUParticles3D.new()
	# particles.emitting = true
	# particles.one_shot = true
	# get_tree().current_scene.add_child(particles)
	# particles.global_position = global_position


func _despawn() -> void:
	## Clean up the projectile
	## Could play fade-out animation here first
	queue_free()
