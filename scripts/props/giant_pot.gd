class_name GiantPot
extends Node3D
## A large clay flower pot - think: player is the size of a seed, pot is 2m+ tall
## Has collision - player can jump on it
## Has "cracked" version with missing chunks (can hide inside)

signal player_entered_pot(player: Node3D)
signal player_exited_pot(player: Node3D)

## Pot variants
enum PotVariant {
	INTACT,   # Full, normal pot
	CRACKED,  # Has a hiding hole in the side
}

## Which variant of the pot this is
@export var variant: PotVariant = PotVariant.INTACT: set = _set_variant

## The pot's height in meters (should feel HUGE from player perspective)
@export_range(1.5, 4.0) var pot_height: float = 2.5: set = _set_pot_height

@onready var _collision_body: StaticBody3D = $CollisionBody
@onready var _mesh_root: Node3D = $MeshRoot
@onready var _hiding_area: Area3D = $HidingArea

var _player_hiding: bool = false
var _player_ref: Node3D = null


func _ready() -> void:
	_update_variant()
	_update_pot_height()
	
	# Connect hiding area signals for cracked variant
	if _hiding_area:
		_hiding_area.body_entered.connect(_on_hiding_area_body_entered)
		_hiding_area.body_exited.connect(_on_hiding_area_body_exited)


func _set_variant(value: PotVariant) -> void:
	variant = value
	_update_variant()


func _set_pot_height(value: float) -> void:
	pot_height = value
	_update_pot_height()


func _update_variant() -> void:
	if not is_node_ready():
		return
	
	var intact_mesh: MeshInstance3D = get_node_or_null("MeshRoot/IntactMesh")
	var cracked_mesh: MeshInstance3D = get_node_or_null("MeshRoot/CrackedMesh")
	
	if intact_mesh and cracked_mesh:
		intact_mesh.visible = (variant == PotVariant.INTACT)
		cracked_mesh.visible = (variant == PotVariant.CRACKED)
	
	# Enable/disable hiding area
	if _hiding_area:
		_hiding_area.monitoring = (variant == PotVariant.CRACKED)


func _update_pot_height() -> void:
	if not is_node_ready():
		return
	
	# Scale mesh to match height
	if _mesh_root:
		var scale_factor := pot_height / 2.5  # Base height is 2.5m
		_mesh_root.scale = Vector3(scale_factor, scale_factor, scale_factor)


func _on_hiding_area_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		_player_hiding = true
		_player_ref = body
		player_entered_pot.emit(body)


func _on_hiding_area_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		_player_hiding = false
		_player_ref = null
		player_exited_pot.emit(body)


## Returns true if player is currently hiding in this pot
func is_player_hiding() -> bool:
	return _player_hiding
