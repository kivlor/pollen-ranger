extends Node3D
## Controller for the one-shot Blight cleansing burst.
##
## The moment a surface is purified should feel PUNCHY and satisfying:
## ash chunks blast outward, purple corruption sparks pop, and green
## bloom pollen drifts up as the color "returns" underneath.
## The flash light burns purple then settles to green.

const LIFETIME := 3.0

@onready var _light: OmniLight3D = $FlashLight


func _ready() -> void:
	# Flash burns out fast; hue shifts purple -> green as corruption dies
	var tween := create_tween()
	tween.tween_property(_light, "light_energy", 0.0, 0.7) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
	tween.parallel().tween_property(_light, "light_color",
			Color(0.45, 0.85, 0.3), 0.7)

	get_tree().create_timer(LIFETIME).timeout.connect(queue_free)
