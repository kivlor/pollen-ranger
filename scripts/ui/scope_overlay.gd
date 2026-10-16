extends Control
## Scope overlay for the arm-cannon zoom (issue #9).
##
## The visual work happens in shaders/scope_overlay.gdshader (circular
## mask, subtle vignette, crosshair). This script only keeps the shader's
## aspect uniform in sync with the overlay's size so the scope circle
## stays perfectly round at any window shape.
##
## The parent controller fades this node in/out by tweening modulate:a
## while the right mouse button is held.

@onready var _material: ShaderMaterial = material


func _ready() -> void:
	resized.connect(_update_aspect)
	_update_aspect()


func _update_aspect() -> void:
	if material == null or size.x <= 0.0 or size.y <= 0.0:
		return
	material.set_shader_parameter("aspect", size.x / size.y)
