class_name SoilTileBody
extends StaticBody3D
## Collision body for a single soil tile
## Handles click events and communicates with the parent SoilGrid

## Grid position of this tile
var grid_pos: Vector2i = Vector2i.ZERO

## Reference to the parent SoilGrid
var soil_grid: SoilGrid = null


func _ready() -> void:
	# Connect input event for click detection
	input_event.connect(_on_input_event)


func _on_input_event(_camera: Node, event: InputEvent, _pos: Vector3, _normal: Vector3, _shape_idx: int) -> void:
	# Handle click events for testing
	if event is InputEventMouseButton:
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			# For testing: click to toggle state
			if soil_grid:
				var state := soil_grid.get_tile_state(grid_pos)
				if state == SoilGrid.TileState.BLIGHT:
					soil_grid.cleanse_tile(grid_pos)
