extends Node3D
## Headless smoke test for the Blighted Grub (issue #5).
## Verifies patrol, detection/chase, damage, death burst, player contact
## damage + knockback, and that a real seed projectile kills the grub.
## Run: godot --headless res://scenes/dev/test_grub_smoke.tscn

const GrubScene := preload("res://scenes/enemies/blighted_grub.tscn")
const PlayerScene := preload("res://scenes/player/first_person_player.tscn")

var _grub: BlightedGrub
var _grub_start: Vector3
var _grub_moved := false
var _died := false
var _burst_spawned := false
var _player: CharacterBody3D
var _check_phase := 0
var _elapsed := 0.0


func _ready() -> void:
	# Flat ground on the environment layer (2) so the grub can walk
	var ground := StaticBody3D.new()
	ground.collision_layer = 2
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 0.1, 40)
	shape.shape = box
	shape.position = Vector3(0, -0.05, 0)
	ground.add_child(shape)
	add_child(ground)

	_grub = GrubScene.instantiate()
	add_child(_grub)
	_grub.global_position = Vector3(0, 0.02, 0)
	_grub.died.connect(func(_g): _died = true)
	_grub_start = _grub.global_position

	# Player placed just outside detect radius for phase 1 (patrol check)
	_player = PlayerScene.instantiate()
	add_child(_player)
	_player.global_position = Vector3(9, 0.1, 0)

	print("TEST: setup complete")


func _physics_process(delta: float) -> void:
	_elapsed += delta

	match _check_phase:
		0:
			# Phase 1: after 1.5s of patrol, did the grub move while PATROLing?
			if _elapsed > 1.5:
				var moved: float = _grub.global_position.distance_to(_grub_start)
				_grub_moved = moved > 0.3
				print("TEST: grub moved %.2f m after 1.5s -> %s" % [moved, _grub_moved])
				print("TEST: still PATROLING away from player? -> ", _grub._state == 0)
				_check_phase = 1
				_elapsed = 0.0
		1:
			# Phase 2: bring player close -> should detect and chase
			if _elapsed > 0.1:
				_player.global_position = Vector3(1.5, 0.1, 0)
				_check_phase = 2
				_elapsed = 0.0
		2:
			if _elapsed > 1.0:
				print("TEST: grub detected player and CHASEs? -> ", _grub._state == 1)
				var dist: float = _grub.global_position.distance_to(_player.global_position)
				print("TEST: grub closed distance to %.2f m (was 1.5)" % dist)
				_check_phase = 3
				_elapsed = 0.0
		3:
			# Phase 3: two hits -> should survive both
			if _elapsed > 0.1:
				_check_phase = 4
				_grub.take_damage(10)
				print("TEST: after 1 hit health -> ", _grub._health)
				_elapsed = 0.0
		4:
			# Phase 4: killing hit -> death burst + died signal
			if _elapsed > 0.3:
				_check_phase = 5
				_grub.take_damage(10)
				_elapsed = 0.0
		5:
			if _elapsed > 0.5:
				for c in get_children():
					print("TEST: child -> ", c.name, " (", c.get_class(), ")")
				print("TEST: current_scene = ", get_tree().current_scene.name)
				_burst_spawned = get_tree().current_scene.find_children("BlightCleanseBurst", "", true, false).size() > 0
				print("TEST: death burst spawned? -> ", _burst_spawned)
				print("TEST: grub died signal? -> ", _died)
				_check_phase = 6
				_elapsed = 0.0
		6:
			# Phase 4: player contact damage + knockback via take_damage
			if _elapsed > 0.2:
				_check_phase = 7
				var vel_before: Vector3 = _player.velocity
				_player.take_damage(1, _player.global_position + Vector3.FORWARD)
				print("TEST: player health after 1 hit -> ", _player.current_health, "/", _player.max_health)
				var speed := Vector3(_player.velocity.x, 0, _player.velocity.z).length()
				print("TEST: player knockback speed -> %.2f (before %.2f)" % [speed, Vector3(vel_before.x, 0, vel_before.z).length()])
				print("TEST: flash node alpha -> %.2f" % _player.get_node("DamageFeedback/Flash").color.a)
				_elapsed = 0.0
		7:
			if _elapsed > 1.0:
				print("TEST: grub freed after death? -> ", not is_instance_valid(_grub))
				var all_pass: bool = _grub_moved and _died and _burst_spawned
				print("TEST RESULT: ", "PASS" if all_pass else "FAIL")
				# Phase 8: fire a REAL seed projectile at a fresh grub
				_grub = GrubScene.instantiate()
				add_child(_grub)
				_grub.global_position = Vector3(10, 0.02, 0)
				_player.global_position = Vector3(30, 0.1, 0)  # keep player far
				var seed_scene: PackedScene = load("res://scenes/player/seed_projectile.tscn")
				var seed: RigidBody3D = seed_scene.instantiate()
				get_tree().current_scene.add_child(seed)
				seed.global_position = Vector3(8, 0.1, 0)
				seed.initialize(Vector3(1, 0, 0))
				_check_phase = 8
				_elapsed = 0.0
		8:
			if _elapsed > 1.5:
				var grub_dead: bool = not is_instance_valid(_grub) or _grub._state == 2
				print("TEST: seed projectile killed grub? -> ", grub_dead)
				get_tree().quit()
				return
			if _elapsed > 0.5 and is_instance_valid(_grub):
				print("TEST: grub health after seed flight -> ", _grub._health)
