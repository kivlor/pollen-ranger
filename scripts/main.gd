extends Node3D
## Main game scene - orchestrates player, environment, and game state

@onready var _player: Node3D = $Player
@onready var _environment: Node3D = $Environment
@onready var _projectiles: Node3D = $Projectiles
@onready var _blight: Node3D = $Blight


func _ready() -> void:
	print("=== Pollen Ranger ===")
	print("A thumb-sized scout's journey to purge the Blight")


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			get_tree().quit()
