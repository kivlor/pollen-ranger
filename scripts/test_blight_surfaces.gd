extends Node3D
## Test scene for the Blight corruption visual system (issue #4).
##
## Shows Blight applied to ground, pots, a trellis and a hanging basket.
##
## Controls (via test_player):
## - WASD move, Space jump, mouse look, left-click shoot seeds
## - C: cleanse ALL blighted surfaces (watch the burst!)
## - B: re-blight everything (fully corrupted)
##
## Auto-demo:
## - PotGrowing starts clean and creeps toward full corruption over ~20s
## - After 15s, the ground auto-cleanses once to demo the burst

const CLEANSE_KEY := KEY_C
const BLIGHT_KEY := KEY_B

## Seconds before the auto-demo cleanse fires
@export var auto_cleanse_delay: float = 15.0

var _auto_cleanse_done: bool = false

@onready var _ground_surface: BlightSurface = $Ground/BlightSurface


func _ready() -> void:
	var surfaces := get_tree().get_nodes_in_group("blight_surface")
	print("[BlightTest] %d BlightSurface nodes active. " % surfaces.size()
			+ "Controls: C = cleanse all, B = blight all. "
			+ "Watch PotGrowing creep over time.")
	if auto_cleanse_delay > 0.0:
		get_tree().create_timer(auto_cleanse_delay).timeout.connect(_auto_cleanse)


func _auto_cleanse() -> void:
	if _auto_cleanse_done or not is_instance_valid(_ground_surface):
		return
	_auto_cleanse_done = true
	print("[BlightTest] Auto-demo: cleansing the ground")
	_ground_surface.cleanse()


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return

	if key.keycode == CLEANSE_KEY:
		for surface in get_tree().get_nodes_in_group("blight_surface"):
			surface.cleanse()
		print("[BlightTest] Cleansed all surfaces")
	elif key.keycode == BLIGHT_KEY:
		for surface in get_tree().get_nodes_in_group("blight_surface"):
			surface.corruption = 1.0
		print("[BlightTest] Fully corrupted all surfaces")
