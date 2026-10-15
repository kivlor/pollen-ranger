class_name TutorialPrompt
extends Node3D
## World-space tutorial prompt for the Entrance Conservatory.
##
## A floating billboard label that fades in when the player walks into its
## trigger volume and fades out when they leave. Zero UI code in the level
## scene — drop one anywhere with a message and a trigger size.
##
## Feel goals (DESIGN.md):
## - Reads like a carved wooden garden sign: helpful, calm, never nagging

## Text shown on the sign (supports \n for multi-line)
@export var message: String = "Move: WASD"

## Size of the trigger volume that reveals the prompt
@export var trigger_size: Vector3 = Vector3(6.0, 3.0, 6.0)

## If true, the prompt stays visible after the player walks past
@export var persist_after_exit: bool = false

## Seconds for the fade in/out
@export var fade_time: float = 0.4

@onready var _area: Area3D = $Area3D
@onready var _label: Label3D = $Label3D

var _fade_tween: Tween


func _ready() -> void:
	_label.text = message

	## Build the trigger box from the exported size
	var shape := BoxShape3D.new()
	shape.size = trigger_size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	_area.add_child(collision)
	_area.collision_layer = 0
	_area.collision_mask = 1  # Player only

	_area.body_entered.connect(_on_body_entered)
	_area.body_exited.connect(_on_body_exited)

	## Start hidden
	var start_alpha := _label.modulate.a
	_label.modulate.a = 0.0


func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	_fade_to(1.0)


func _on_body_exited(body: Node3D) -> void:
	if not body.is_in_group("player") or persist_after_exit:
		return
	_fade_to(0.0)


func _fade_to(target_alpha: float) -> void:
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()

	_fade_tween = create_tween()
	_fade_tween.tween_property(_label, "modulate:a", target_alpha, fade_time) \
			.set_ease(Tween.EASE_OUT)
