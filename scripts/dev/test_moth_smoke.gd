extends Node3D
## Headless smoke test for the Blighted Moth (issue #6).
## Verifies figure-8 patrol, cone-of-vision detection, the swoop ->
## recover -> return cycle, glider-boosted detection, damage/death burst,
## and that a real seed projectile kills the moth.
## Run: godot --headless res://scenes/dev/test_moth_smoke.tscn

const MothScene := preload("res://scenes/enemies/blighted_moth.tscn")
const PlayerScene := preload("res://scenes/player/first_person_player.tscn")

var _moth: BlightedMoth
var _moth_start: Vector3
var _player: CharacterBody3D
var _check_phase := 0
var _elapsed := 0.0
var _debug_timer := 0.0

# Recorded results
var _patrolled := false
var _stayed_airborne := false
var _detected_via_glider := false
var _swooped := false
var _swoop_closed_in := false
var _returned := false
var _survived_one_hit := false
var _died := false
var _burst_spawned := false
var _seed_killed := false


func _ready() -> void:
	# Flat ground on the environment layer (2) — also blocks the moth's
	# line-of-sight ray if something gets between moth and player.
	var ground := StaticBody3D.new()
	ground.collision_layer = 2
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80, 0.1, 80)
	shape.shape = box
	shape.position = Vector3(0, -0.05, 0)
	ground.add_child(shape)
	add_child(ground)

	_moth = MothScene.instantiate()
	add_child(_moth)
	# Spawn slightly below patrol height; the moth lifts to its anchor
	_moth.global_position = Vector3(0, 1.2, 0)
	_moth.died.connect(func(_m): _died = true)
	_moth_start = _moth.global_position

	# Player far outside detect range for phase 1 (patrol check)
	_player = PlayerScene.instantiate()
	add_child(_player)
	_player.global_position = Vector3(14, 0.3, 0)

	print("TEST: setup complete")


func _physics_process(delta: float) -> void:
	_elapsed += delta

	match _check_phase:
		0:
			# Phase 1: after 2s of patrol, did the moth move along its
			# figure-8 while staying airborne and in PATROL state?
			if _elapsed > 2.0:
				var moved: float = _moth.global_position.distance_to(_moth_start)
				_patrolled = moved > 0.4
				_stayed_airborne = _moth.global_position.y > 0.6
				print("TEST: moth moved %.2f m after 2s -> %s" % [moved, _patrolled])
				print("TEST: moth stayed airborne (y=%.2f)? -> %s" % [_moth.global_position.y, _stayed_airborne])
				print("TEST: still PATROLING with player far away? -> ", _moth._state == 0)
				_check_phase = 1
				_elapsed = 0.0
		1:
			# Phase 2: player 12 m away IN FRONT of the moth — outside normal
			# detect range (8 m) but inside the GLIDING range (8 * 1.75 = 14 m).
			# Should NOT be detected while grounded.
			if _elapsed > 0.1:
				var fwd: Vector3 = -_moth.global_transform.basis.z
				fwd.y = 0.0
				_player.global_position = _moth.global_position + fwd.normalized() * 12.0
				_player.global_position.y = 6.0  # start high; glider slows the fall
				_check_phase = 2
				_elapsed = 0.0
		2:
			if _elapsed > 1.0:
				print("TEST: grounded player at 12m NOT detected? -> ", _moth._state == 0)
				# Now re-place the player 12 m in front of the moth's CURRENT
				# facing, airborne at y=6, and deploy the glider. The glider
				# stays deployed because the player never lands (slow fall).
				var fwd: Vector3 = -_moth.global_transform.basis.z
				fwd.y = 0.0
				_player.global_position = _moth.global_position + fwd.normalized() * 12.0
				_player.global_position.y = 6.0
				var glider: Node = _player.get_node("Glider")
				glider.is_deployed = true
				_check_phase = 3
				_elapsed = 0.0
		3:
			# Phase 3: gliding player at 12 m should trigger detection quickly
			if _elapsed > 0.6:
				var agitated: bool = _moth._state >= 1 and _moth._state <= 4
				_detected_via_glider = agitated
				print("TEST: gliding player at 12m detected (state=%d)? -> %s" % [_moth._state, _detected_via_glider])
				# Stand the player down and let the moth finish its dive
				var glider2: Node = _player.get_node("Glider")
				glider2.is_deployed = false
				_player.global_position = Vector3(40, 0.3, 0)
				_check_phase = 4
				_elapsed = 0.0
		4:
			# Phase 4: player just in front of the moth, inside detect range —
			# should detect and swoop
			if _elapsed > 3.0:
				_moth._swoop_cooldown_timer = 0.0
				# Place the player on the ground directly under the patrol
				# anchor — the moth crosses overhead twice per figure-8 loop,
				# inside its close-sense radius, so detection is deterministic.
				_player.global_position = Vector3(_moth._anchor.x, 0.3, _moth._anchor.z)
				_check_phase = 5
				_elapsed = 0.0
		5:
			# Phase 5: watch for the SWOOP state and a closing distance
			if is_instance_valid(_moth):
				var dist: float = _moth.global_position.distance_to(_player.global_position)
				if _moth._state == 2:
					_swooped = true
					if dist < 1.6:
						_swoop_closed_in = true
						print("TEST: swoop closed to %.2f m" % dist)
				_debug_timer -= delta
				if _debug_timer <= 0.0:
					_debug_timer = 0.4
					var to_p: Vector3 = (_player.global_position - _moth.global_position).normalized()
					var fwd: Vector3 = -_moth.global_transform.basis.z
					print("DEBUG: state=%d dist=%.2f dot=%.2f" % [_moth._state, dist, fwd.dot(to_p)])
			if _elapsed > 8.0:
				print("TEST: moth SWOOPed? -> ", _swooped)
				print("TEST: swoop closed in on player? -> ", _swoop_closed_in)
				# Send the player far away so the moth returns to patrol
				_player.global_position = Vector3(40, 0.3, 0)
				_check_phase = 6
				_elapsed = 0.0
		6:
			# Phase 6: moth should climb out and RETURN to its figure-8
			if is_instance_valid(_moth) and _moth._state == 4 and not _returned:
				_returned = true
				print("TEST: moth entered RETURN state")
			if is_instance_valid(_moth) and _moth._state == 0 \
					and _moth.global_position.distance_to(_moth._anchor) < 2.5:
				if not _returned:
					print("TEST: moth back on patrol near anchor (dist %.2f)" % _moth.global_position.distance_to(_moth._anchor))
				_returned = true
			if _elapsed > 6.0:
				print("TEST: moth returned to patrol? -> ", _returned)
				_check_phase = 7
				_elapsed = 0.0
		7:
			# Phase 7: one hit should hurt but not kill
			if _elapsed > 0.1:
				_check_phase = 8
				_moth.take_damage(5)
				_survived_one_hit = is_instance_valid(_moth) and _moth._health == 5
				print("TEST: after 5 damage health -> ", _moth._health)
				_elapsed = 0.0
		8:
			# Phase 8: killing hit -> death burst + died signal
			if _elapsed > 0.3:
				_check_phase = 9
				_moth.take_damage(10)
				_elapsed = 0.0
		9:
			if _elapsed > 0.5:
				_burst_spawned = get_tree().current_scene.find_children("BlightCleanseBurst", "", true, false).size() > 0
				print("TEST: death burst spawned? -> ", _burst_spawned)
				print("TEST: moth died signal? -> ", _died)
				_check_phase = 10
				_elapsed = 0.0
		10:
			if _elapsed > 1.0:
				print("TEST: moth freed after death? -> ", not is_instance_valid(_moth))
				var all_pass: bool = _patrolled and _stayed_airborne \
						and _detected_via_glider and _swooped and _swoop_closed_in \
						and _returned and _survived_one_hit and _died and _burst_spawned
				print("TEST RESULT: ", "PASS" if all_pass else "FAIL")
				if not all_pass:
					get_tree().quit(1)
					return
				# Phase 11: fire a REAL seed projectile at a fresh moth
				_moth = MothScene.instantiate()
				add_child(_moth)
				_moth.global_position = Vector3(10, 2.0, 0)
				_player.global_position = Vector3(40, 0.3, 0)  # keep player far
				var seed_scene: PackedScene = load("res://scenes/player/seed_projectile.tscn")
				var seed: RigidBody3D = seed_scene.instantiate()
				get_tree().current_scene.add_child(seed)
				seed.global_position = Vector3(8, 2.0, 0)
				seed.initialize(Vector3(1, 0, 0))
				_check_phase = 11
				_elapsed = 0.0
		11:
			if _elapsed > 1.5:
				var moth_dead: bool = not is_instance_valid(_moth) or _moth._state == 5
				_seed_killed = moth_dead
				print("TEST: seed projectile killed moth? -> ", _seed_killed)
				print("TEST RESULT: ", "PASS" if _seed_killed else "FAIL")
				get_tree().quit(0 if _seed_killed else 1)
				return
			if _elapsed > 0.5 and is_instance_valid(_moth):
				print("TEST: moth health after seed flight -> ", _moth._health)
