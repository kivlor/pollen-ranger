class_name SoilGrid
extends Node3D
## A grid of soil tiles that can be BLIGHT, NEUTRAL, or BLOOM
## Core "reclamation" mechanic for Pollen Ranger
##
## Features:
## - Visual shader-based blending between states
## - Particle effects when tiles are cleansed
## - Blight propagation over time
## - Zone cleansing detection (80%+ BLOOM)

signal tile_cleansed(grid_pos: Vector2i, new_state: TileState)
signal tile_corrupted(grid_pos: Vector2i, new_state: TileState)
signal zone_cleansed(bloom_percentage: float)

enum TileState {
	BLIGHT,  # Corrupted, gray - needs cleansing
	NEUTRAL, # Normal soil - can become either
	BLOOM,   # Cleansed, lush - player benefit
}

## === GRID CONFIGURATION ===
@export var grid_width: int = 10
@export var grid_height: int = 10
@export var tile_size: float = 1.0

## Initial state for all tiles (for testing, can be changed)
@export var initial_state: TileState = TileState.BLIGHT

## Initial blight pattern: 0.0 = all NEUTRAL, 1.0 = all BLIGHT
@export var initial_blight_coverage: float = 0.7

## === PROPAGATION CONFIGURATION ===
## How often blight spreads (in seconds)
@export var blight_spread_interval: float = 2.0

## Chance per adjacent tile for blight to spread (0.0-1.0)
@export var blight_spread_chance: float = 0.15

## BLOOM resistance to corruption (higher = harder to corrupt)
@export var bloom_resistance: float = 0.8

## === ZONE CLEANSING ===
## Threshold for zone to be considered "cleansed" (0.0-1.0)
@export var cleanse_threshold: float = 0.8

## === NODE REFERENCES ===
@onready var _tiles_root: Node3D = $TilesRoot

## === STATE ===
var _tile_states: Array[Array] = []  # 2D array of TileState
var _tile_meshes: Dictionary = {}    # GridPos -> MeshInstance3D
var _tile_materials: Dictionary = {} # GridPos -> ShaderMaterial (for shader control)
var _glow_timers: Dictionary = {}    # GridPos -> Timer (for glow fade)

var _time_since_spread: float = 0.0
var _zone_cleansed: bool = false
var _bloom_count: int = 0
var _blight_count: int = 0

## Preload shader and effects
const SoilShader := preload("res://shaders/soil.gdshader")
const CleansingEffectScene := preload("res://scenes/effects/cleansing_effect.tscn")
const SoilTileBodyScript := preload("res://scripts/props/soil_tile_body.gd")

# Legacy materials (fallback if shader fails)
var _material_blight: StandardMaterial3D
var _material_neutral: StandardMaterial3D
var _material_bloom: StandardMaterial3D


func _ready() -> void:
	# Load fallback materials
	_material_blight = preload("res://assets/materials/soil_blight.tres")
	_material_neutral = preload("res://assets/materials/soil.tres")
	_material_bloom = preload("res://assets/materials/soil_bloom.tres")
	
	_initialize_grid()
	_generate_visual_grid()
	
	# Connect to own signals for particle effects
	tile_cleansed.connect(_on_tile_cleansed)
	
	# Set some initial blight pattern for testing
	_setup_initial_blight()
	
	print("[SoilGrid] Initialized %dx%d grid with %d BLIGHT tiles" % [
		grid_width, grid_height, _blight_count
	])


func _initialize_grid() -> void:
	_tile_states.clear()
	_bloom_count = 0
	_blight_count = 0
	
	for x in range(grid_width):
		var column: Array[TileState] = []
		for y in range(grid_height):
			column.append(TileState.NEUTRAL)
		_tile_states.append(column)


func _setup_initial_blight() -> void:
	"""Setup initial blight pattern for testing."""
	# Use random pattern based on coverage
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(global_position)  # Deterministic based on position
	
	for x in range(grid_width):
		for y in range(grid_height):
			if rng.randf() < initial_blight_coverage:
				_tile_states[x][y] = TileState.BLIGHT
				_blight_count += 1
			else:
				_tile_states[x][y] = TileState.NEUTRAL
	
	# Update visuals after setting states
	_update_all_tile_visuals()


func _generate_visual_grid() -> void:
	"""Generate visual mesh for each tile."""
	# Clear existing tiles
	if _tiles_root:
		for child in _tiles_root.get_children():
			child.queue_free()
	
	_tile_meshes.clear()
	_tile_materials.clear()
	_glow_timers.clear()
	
	# Create tile meshes
	for x in range(grid_width):
		for y in range(grid_height):
			var tile := _create_tile_mesh(x, y)
			if _tiles_root and tile:
				_tiles_root.add_child(tile)
				_tile_meshes[Vector2i(x, y)] = tile


func _create_tile_mesh(x: int, y: int) -> MeshInstance3D:
	var tile := MeshInstance3D.new()
	tile.name = "Tile_%d_%d" % [x, y]
	tile.mesh = BoxMesh.new()
	tile.mesh.size = Vector3(tile_size * 0.95, 0.1, tile_size * 0.95)
	
	# Position the tile
	tile.position = Vector3(
		x * tile_size + tile_size / 2.0 - grid_width * tile_size / 2.0,
		0,
		y * tile_size + tile_size / 2.0 - grid_height * tile_size / 2.0
	)
	
	# Create shader material for this tile
	var shader_mat := ShaderMaterial.new()
	shader_mat.shader = SoilShader
	shader_mat.set_shader_parameter("bloom_factor", _get_bloom_factor_for_state(_tile_states[x][y]))
	shader_mat.set_shader_parameter("glow_intensity", 0.0)
	shader_mat.set_shader_parameter("time", 0.0)
	
	tile.material_override = shader_mat
	_tile_materials[Vector2i(x, y)] = shader_mat
	
	# Create glow timer for this tile
	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = 0.8
	timer.name = "GlowTimer"
	tile.add_child(timer)
	_glow_timers[Vector2i(x, y)] = timer
	
	# Add collision for seed projectile detection
	var body := SoilTileBody.new()
	body.collision_layer = 16  # Layer 4: blight/soil
	body.collision_mask = 32   # Layer 5: projectiles
	body.name = "CollisionBody"
	body.grid_pos = Vector2i(x, y)
	body.soil_grid = self
	
	var collision := CollisionShape3D.new()
	collision.shape = BoxShape3D.new()
	collision.shape.size = tile.mesh.size
	body.add_child(collision)
	
	tile.add_child(body)
	
	return tile


func _get_bloom_factor_for_state(state: TileState) -> float:
	match state:
		TileState.BLIGHT:
			return 0.0
		TileState.BLOOM:
			return 1.0
		_:  # NEUTRAL
			return 0.5


func _update_all_tile_visuals() -> void:
	"""Update visual appearance of all tiles based on their state."""
	for x in range(grid_width):
		for y in range(grid_height):
			var pos := Vector2i(x, y)
			if _tile_materials.has(pos):
				var mat: ShaderMaterial = _tile_materials[pos]
				mat.set_shader_parameter("bloom_factor", _get_bloom_factor_for_state(_tile_states[x][y]))


func _process(delta: float) -> void:
	# Update shader time for animated noise
	for pos in _tile_materials.keys():
		var mat: ShaderMaterial = _tile_materials[pos]
		mat.set_shader_parameter("time", Time.get_ticks_msec() / 1000.0)
	
	# Handle blight propagation
	_process_blight_spread(delta)


func _process_blight_spread(delta: float) -> void:
	"""Handle periodic blight spreading to adjacent tiles."""
	_time_since_spread += delta
	
	if _time_since_spread < blight_spread_interval:
		return
	
	_time_since_spread = 0.0
	
	# Collect all BLIGHT tiles and try to spread from each
	var blight_tiles: Array[Vector2i] = []
	for x in range(grid_width):
		for y in range(grid_height):
			if _tile_states[x][y] == TileState.BLIGHT:
				blight_tiles.append(Vector2i(x, y))
	
	# Shuffle to make spread more organic
	blight_tiles.shuffle()
	
	var rng := RandomNumberGenerator.new()
	
	for blight_pos in blight_tiles:
		var neighbors := _get_adjacent_tiles(blight_pos)
		for neighbor in neighbors:
			var neighbor_state := get_tile_state(neighbor)
			if neighbor_state == TileState.NEUTRAL:
				# Try to spread to NEUTRAL
				if rng.randf() < blight_spread_chance:
					_corrupt_tile_internal(neighbor)
			elif neighbor_state == TileState.BLOOM:
				# BLOOM resists corruption
				var corrupt_chance := blight_spread_chance * (1.0 - bloom_resistance)
				if rng.randf() < corrupt_chance:
					_corrupt_tile_internal(neighbor)


func _get_adjacent_tiles(pos: Vector2i) -> Array[Vector2i]:
	"""Get valid adjacent tile positions (4-directional)."""
	var neighbors: Array[Vector2i] = []
	var offsets := [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]
	
	for offset in offsets:
		var neighbor: Vector2i = pos + offset
		if _is_valid_pos(neighbor):
			neighbors.append(neighbor)
	
	return neighbors


func _corrupt_tile_internal(grid_pos: Vector2i) -> void:
	"""Internal corruption without triggering cleanse effects."""
	if not _is_valid_pos(grid_pos):
		return
	
	var old_state: TileState = _tile_states[grid_pos.x][grid_pos.y]
	if old_state == TileState.BLIGHT:
		return
	
	_tile_states[grid_pos.x][grid_pos.y] = TileState.BLIGHT
	
	# Update counts
	if old_state == TileState.BLOOM:
		_bloom_count -= 1
	elif old_state == TileState.NEUTRAL:
		pass
	_blight_count += 1
	
	# Update visual
	if _tile_materials.has(grid_pos):
		var mat: ShaderMaterial = _tile_materials[grid_pos]
		mat.set_shader_parameter("bloom_factor", 0.0)
	
	tile_corrupted.emit(grid_pos, TileState.BLIGHT)
	
	# Reset zone cleansed flag if we were cleansed
	if _zone_cleansed:
		_zone_cleansed = false
		print("[SoilGrid] Zone no longer cleansed - blight spreading!")


## === PUBLIC API ===

func get_tile_state(grid_pos: Vector2i) -> TileState:
	if _is_valid_pos(grid_pos):
		return _tile_states[grid_pos.x][grid_pos.y]
	return TileState.NEUTRAL


func set_tile_state(grid_pos: Vector2i, state: TileState) -> void:
	if not _is_valid_pos(grid_pos):
		return
	
	var old_state: TileState = _tile_states[grid_pos.x][grid_pos.y]
	if old_state == state:
		return
	
	_tile_states[grid_pos.x][grid_pos.y] = state
	
	# Update counts
	match old_state:
		TileState.BLIGHT:
			_blight_count -= 1
		TileState.BLOOM:
			_bloom_count -= 1
	
	match state:
		TileState.BLIGHT:
			_blight_count += 1
		TileState.BLOOM:
			_bloom_count += 1
	
	# Update visual
	if _tile_materials.has(grid_pos):
		var mat: ShaderMaterial = _tile_materials[grid_pos]
		mat.set_shader_parameter("bloom_factor", _get_bloom_factor_for_state(state))
	
	# Emit signal
	if state == TileState.BLOOM and old_state != TileState.BLOOM:
		tile_cleansed.emit(grid_pos, state)
	elif state == TileState.BLIGHT and old_state != TileState.BLIGHT:
		tile_corrupted.emit(grid_pos, state)
	
	# Check zone cleansing
	_check_zone_cleansing()


func cleanse_tile(grid_pos: Vector2i) -> void:
	"""Convert a BLIGHT tile to BLOOM (called by seed projectile hit)."""
	if get_tile_state(grid_pos) == TileState.BLIGHT:
		set_tile_state(grid_pos, TileState.BLOOM)


func corrupt_tile(grid_pos: Vector2i) -> void:
	"""Convert a tile to BLIGHT."""
	set_tile_state(grid_pos, TileState.BLIGHT)


func world_to_grid(world_pos: Vector3) -> Vector2i:
	"""Convert world position to grid coordinates."""
	var local_pos := world_pos - global_position
	var grid_x := int((local_pos.x + grid_width * tile_size / 2.0) / tile_size)
	var grid_y := int((local_pos.z + grid_height * tile_size / 2.0) / tile_size)
	return Vector2i(grid_x, grid_y)


func grid_to_world(grid_pos: Vector2i) -> Vector3:
	"""Get world position for center of a grid tile."""
	return Vector3(
		grid_pos.x * tile_size + tile_size / 2.0 - grid_width * tile_size / 2.0,
		0,
		grid_pos.y * tile_size + tile_size / 2.0 - grid_height * tile_size / 2.0
	) + global_position


func get_bloom_percentage() -> float:
	"""Get the percentage of the grid that is BLOOM state."""
	var total_tiles := grid_width * grid_height
	if total_tiles == 0:
		return 0.0
	return float(_bloom_count) / float(total_tiles)


func is_zone_cleansed() -> bool:
	"""Check if the zone has been cleansed (80%+ BLOOM)."""
	return _zone_cleansed


## === PRIVATE ===

func _check_zone_cleansing() -> void:
	"""Check if the zone meets the cleansing threshold."""
	if _zone_cleansed:
		return
	
	var bloom_pct := get_bloom_percentage()
	if bloom_pct >= cleanse_threshold:
		_zone_cleansed = true
		zone_cleansed.emit(bloom_pct)
		print("[SoilGrid] === ZONE CLEANSED! === %.1f%% BLOOM" % (bloom_pct * 100))


func _on_tile_cleansed(grid_pos: Vector2i, _new_state: TileState) -> void:
	"""Spawn particle effect when a tile is cleansed."""
	_spawn_cleansing_particles(grid_pos)
	_trigger_glow_effect(grid_pos)


func _spawn_cleansing_particles(grid_pos: Vector2i) -> void:
	"""Spawn the cleansing particle burst at the tile position."""
	var world_pos := grid_to_world(grid_pos)
	
	if CleansingEffectScene:
		var effect: Node3D = CleansingEffectScene.instantiate()
		get_tree().current_scene.add_child(effect)
		effect.global_position = world_pos + Vector3(0, 0.05, 0)  # Slightly above ground
	else:
		push_warning("[SoilGrid] Could not load cleansing effect scene")


func _trigger_glow_effect(grid_pos: Vector2i) -> void:
	"""Trigger a brief glow effect on the tile when cleansed."""
	if not _tile_materials.has(grid_pos):
		return
	
	var mat: ShaderMaterial = _tile_materials[grid_pos]
	
	# Set glow intensity
	mat.set_shader_parameter("glow_intensity", 1.0)
	
	# Create a tween to fade out the glow
	var tween := create_tween()
	tween.tween_property(mat, "shader_parameter/glow_intensity", 0.0, 0.8)
	
	# Also tween the bloom_factor for smooth transition
	# (Already set to 1.0 by set_tile_state)


func _is_valid_pos(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.x < grid_width and pos.y >= 0 and pos.y < grid_height
