class_name SoilGrid
extends Node3D
## A grid of soil tiles that can be BLIGHT or BLOOM
## Used for ground surfaces in the greenhouse
## Integrates with the game's cleansing mechanics

signal tile_cleansed(grid_pos: Vector2i, new_state: TileState)
signal tile_corrupted(grid_pos: Vector2i, new_state: TileState)

enum TileState {
	BLIGHT,  # Corrupted, gray - needs cleansing
	NEUTRAL, # Normal soil - can become either
	BLOOM,   # Cleansed, lush - player benefit
}

## Grid dimensions
@export var grid_width: int = 10
@export var grid_height: int = 10
@export var tile_size: float = 1.0

## Initial state for all tiles
@export var initial_state: TileState = TileState.NEUTRAL

@onready var _tiles_root: Node3D = $TilesRoot

var _tile_states: Array[Array] = []  # 2D array of TileState
var _tile_meshes: Dictionary = {}    # GridPos -> MeshInstance3D

# Materials
var _material_blight: StandardMaterial3D
var _material_neutral: StandardMaterial3D
var _material_bloom: StandardMaterial3D


func _ready() -> void:
	# Load materials
	_material_blight = preload("res://assets/materials/soil_blight.tres")
	_material_neutral = preload("res://assets/materials/soil.tres")
	_material_bloom = preload("res://assets/materials/soil_bloom.tres")
	
	_initialize_grid()
	_generate_visual_grid()


func _initialize_grid() -> void:
	_tile_states.clear()
	for x in range(grid_width):
		var column: Array[TileState] = []
		for y in range(grid_height):
			column.append(initial_state)
		_tile_states.append(column)


func _generate_visual_grid() -> void:
	# Clear existing tiles
	if _tiles_root:
		for child in _tiles_root.get_children():
			child.queue_free()
	
	_tile_meshes.clear()
	
	# Create tile meshes
	for x in range(grid_width):
		for y in range(grid_height):
			var tile := _create_tile_mesh(x, y)
			if _tiles_root and tile:
				_tiles_root.add_child(tile)
				_tile_meshes[Vector2i(x, y)] = tile


func _create_tile_mesh(x: int, y: int) -> MeshInstance3D:
	var tile := MeshInstance3D.new()
	tile.mesh = BoxMesh.new()
	tile.mesh.size = Vector3(tile_size * 0.95, 0.1, tile_size * 0.95)
	
	# Position the tile
	tile.position = Vector3(
		x * tile_size + tile_size / 2.0 - grid_width * tile_size / 2.0,
		0,
		y * tile_size + tile_size / 2.0 - grid_height * tile_size / 2.0
	)
	
	# Apply material based on state
	tile.material_override = _get_material_for_state(_tile_states[x][y])
	
	# Add collision
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	collision.shape = BoxShape3D.new()
	collision.shape.size = tile.mesh.size
	body.add_child(collision)
	tile.add_child(body)
	
	return tile


func _get_material_for_state(state: TileState) -> StandardMaterial3D:
	match state:
		TileState.BLIGHT:
			return _material_blight
		TileState.BLOOM:
			return _material_bloom
		_:
			return _material_neutral


## Get the state of a specific tile
func get_tile_state(grid_pos: Vector2i) -> TileState:
	if _is_valid_pos(grid_pos):
		return _tile_states[grid_pos.x][grid_pos.y]
	return TileState.NEUTRAL


## Set the state of a specific tile
func set_tile_state(grid_pos: Vector2i, state: TileState) -> void:
	if not _is_valid_pos(grid_pos):
		return
	
	var old_state := _tile_states[grid_pos.x][grid_pos.y]
	_tile_states[grid_pos.x][grid_pos.y] = state
	
	# Update visual
	if _tile_meshes.has(grid_pos):
		var tile: MeshInstance3D = _tile_meshes[grid_pos]
		tile.material_override = _get_material_for_state(state)
	
	# Emit signal
	if state != old_state:
		if state == TileState.BLOOM:
			tile_cleansed.emit(grid_pos, state)
		elif state == TileState.BLIGHT:
			tile_corrupted.emit(grid_pos, state)


## Cleanse a tile (BLIGHT -> BLOOM)
func cleanse_tile(grid_pos: Vector2i) -> void:
	if get_tile_state(grid_pos) == TileState.BLIGHT:
		set_tile_state(grid_pos, TileState.BLOOM)


## Corrupt a tile (any -> BLIGHT)
func corrupt_tile(grid_pos: Vector2i) -> void:
	set_tile_state(grid_pos, TileState.BLIGHT)


## Convert world position to grid position
func world_to_grid(world_pos: Vector3) -> Vector2i:
	var local_pos := world_pos - global_position
	var grid_x := int((local_pos.x + grid_width * tile_size / 2.0) / tile_size)
	var grid_y := int((local_pos.z + grid_height * tile_size / 2.0) / tile_size)
	return Vector2i(grid_x, grid_y)


## Get world position for grid center
func grid_to_world(grid_pos: Vector2i) -> Vector3:
	return Vector3(
		grid_pos.x * tile_size + tile_size / 2.0 - grid_width * tile_size / 2.0,
		0,
		grid_pos.y * tile_size + tile_size / 2.0 - grid_height * tile_size / 2.0
	) + global_position


func _is_valid_pos(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.x < grid_width and pos.y >= 0 and pos.y < grid_height
