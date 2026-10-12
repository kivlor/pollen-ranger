class_name HangingBasket
extends Node3D
## A basket suspended from above (chains or vines)
## Has physics: gentle swaying motion
## Player can land on it (glider target)
## Basket contains soil that can be BLIGHT or BLOOM

signal soil_state_changed(new_state: String)
signal player_landed(player: Node3D)
signal player_left(player: Node3D)

## How the basket is suspended
enum SuspensionType {
	CHAIN,
	VINE,
}

## The state of the soil inside
enum SoilState {
	BLIGHT,  # Corrupted, gray
	NEUTRAL, # Normal soil
	BLOOM,   # Cleansed, lush
}

## Suspension type (affects visuals and sway characteristics)
@export var suspension_type: SuspensionType = SuspensionType.CHAIN

## The current soil state
@export var soil_state: SoilState = SoilState.NEUTRAL: set = _set_soil_state

## How much the basket sways (0.0 = static, 1.0 = very wobbly)
@export_range(0.0, 1.0) var sway_amount: float = 0.3

## Sway period in seconds
@export_range(1.0, 10.0) var sway_period: float = 4.0

## Chain/vine length (how high above the basket)
@export_range(0.5, 5.0) var chain_length: float = 1.5

@onready var _basket_mesh: MeshInstance3D = $BasketMesh
@onready var _soil_mesh: MeshInstance3D = $SoilMesh
@onready var _landing_area: Area3D = $LandingArea
@onready var _suspension_root: Node3D = $SuspensionRoot

var _time_offset: float = 0.0
var _player_on_basket: bool = false
var _player_ref: Node3D = null

# Material references
var _soil_material_neutral: StandardMaterial3D
var _soil_material_blight: StandardMaterial3D
var _soil_material_bloom: StandardMaterial3D


func _ready() -> void:
	# Load soil materials
	_soil_material_neutral = preload("res://assets/materials/soil.tres")
	_soil_material_blight = preload("res://assets/materials/soil_blight.tres")
	_soil_material_bloom = preload("res://assets/materials/soil_bloom.tres")
	
	# Random time offset for natural variation
	_time_offset = randf() * TAU
	
	# Connect landing area signals
	if _landing_area:
		_landing_area.body_entered.connect(_on_landing_area_body_entered)
		_landing_area.body_exited.connect(_on_landing_area_body_exited)
	
	# Apply initial state
	_apply_soil_state()
	_apply_suspension_type()
	_update_chain_length()


func _physics_process(delta: float) -> void:
	# Calculate gentle swaying motion
	# Should feel peaceful and organic, not frantic
	var time := Time.get_ticks_msec() / 1000.0 + _time_offset
	var sway_x := sin(time * TAU / sway_period) * sway_amount * 0.1
	var sway_z := cos(time * TAU / sway_period * 0.7) * sway_amount * 0.08
	
	# Apply gentle rotation for pendulum effect
	rotation.z = sway_x
	rotation.x = sway_z
	
	# When player is on basket, add extra weight
	if _player_on_basket:
		# Heavier sway when player is on
		rotation.z *= 1.5
		rotation.x *= 1.5


func _set_soil_state(value: SoilState) -> void:
	soil_state = value
	_apply_soil_state()
	soil_state_changed.emit(SoilState.keys()[value])


func _apply_soil_state() -> void:
	if not is_node_ready() or not _soil_mesh:
		return
	
	match soil_state:
		SoilState.BLIGHT:
			_soil_mesh.material_override = _soil_material_blight
		SoilState.BLOOM:
			_soil_mesh.material_override = _soil_material_bloom
		_:
			_soil_mesh.material_override = _soil_material_neutral


func _apply_suspension_type() -> void:
	if not is_node_ready():
		return
	
	# Toggle chain vs vine visuals
	var chain_mesh: MeshInstance3D = get_node_or_null("SuspensionRoot/ChainMesh")
	var vine_mesh: MeshInstance3D = get_node_or_null("SuspensionRoot/VineMesh")
	
	if chain_mesh and vine_mesh:
		chain_mesh.visible = (suspension_type == SuspensionType.CHAIN)
		vine_mesh.visible = (suspension_type == SuspensionType.VINE)
		
		# Vines sway more gently
		if suspension_type == SuspensionType.VINE:
			sway_amount *= 1.2


func _update_chain_length() -> void:
	if not is_node_ready():
		return
	
	# Position the basket based on chain length
	if _basket_mesh:
		_basket_mesh.position.y = -chain_length
	
	if _landing_area:
		_landing_area.position.y = -chain_length


func _on_landing_area_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		_player_on_basket = true
		_player_ref = body
		player_landed.emit(body)


func _on_landing_area_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		_player_on_basket = false
		_player_ref = null
		player_left.emit(body)


## Cleanses the soil from BLIGHT to BLOOM
func cleanse() -> void:
	if soil_state == SoilState.BLIGHT:
		soil_state = SoilState.BLOOM
		# Could add particle effects here for the cleansing moment


## Corrupts the soil to BLIGHT
func corrupt() -> void:
	soil_state = SoilState.BLIGHT
