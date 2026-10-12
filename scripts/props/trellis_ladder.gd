class_name TrellisLadder
extends Node3D
## A climbable wooden trellis structure
## Player can "grab" and move up/down (like a ladder)
## Modular: multiple trellis pieces can snap together vertically

signal player_entered_ladder(player: Node3D)
signal player_exited_ladder(player: Node3D)

## Whether this trellis has vines wrapped around it
@export var has_vines: bool = false

## How many trellis segments are stacked vertically (each is 2m tall)
@export var segments: int = 1: set = _set_segments

## The climbing speed multiplier
@export var climb_speed: float = 2.0

@onready var _climb_area: Area3D = $ClimbArea
@onready var _mesh_root: Node3D = $MeshRoot

var _is_player_in_range: bool = false
var _player_ref: Node3D = null

# Constants for segment height
const SEGMENT_HEIGHT: float = 2.0


func _ready() -> void:
	# Connect climbing area signals
	if _climb_area:
		_climb_area.body_entered.connect(_on_climb_area_body_entered)
		_climb_area.body_exited.connect(_on_climb_area_body_exited)
	
	# Apply vine visual
	_update_vine_visibility()
	_update_segments()


func _set_segments(value: int) -> void:
	segments = max(1, value)
	_update_segments()


func _update_segments() -> void:
	if not is_node_ready():
		return
	
	# Update collision shape for total height
	var collision: CollisionShape3D = get_node_or_null("ClimbArea/CollisionShape3D")
	if collision and collision.shape is BoxShape3D:
		var box_shape: BoxShape3D = collision.shape
		box_shape.size.y = segments * SEGMENT_HEIGHT
		collision.position.y = segments * SEGMENT_HEIGHT / 2.0


func _update_vine_visibility() -> void:
	var vine_mesh: MeshInstance3D = get_node_or_null("MeshRoot/VineMesh")
	if vine_mesh:
		vine_mesh.visible = has_vines


func _on_climb_area_body_entered(body: Node3D) -> void:
	# Check if this is the player
	if body.is_in_group("player"):
		_is_player_in_range = true
		_player_ref = body
		player_entered_ladder.emit(body)


func _on_climb_area_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		_is_player_in_range = false
		_player_ref = null
		player_exited_ladder.emit(body)


## Returns true if player can climb this trellis
func can_climb() -> bool:
	return _is_player_in_range


## Returns the climb direction (up/down) based on player input
func get_climb_input() -> Vector2:
	if not _is_player_in_range:
		return Vector2.ZERO
	
	# This would be connected to player's input system
	var climb_input := Vector2.ZERO
	climb_input.y = Input.get_axis("move_back", "move_forward") * -1
	return climb_input


## Snap this trellis to another trellis piece
func snap_to_trellis(other_trellis: TrellisLadder, vertical_offset: int = 1) -> void:
	global_position = other_trellis.global_position + Vector3(0, vertical_offset * SEGMENT_HEIGHT, 0)
