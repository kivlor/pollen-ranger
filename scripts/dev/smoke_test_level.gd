extends SceneTree
## Headless smoke test for the Entrance Conservatory level.
## Simulates player input through the Input singleton and verifies:
## grounded spawn, forward movement, jumping, seed firing, kill-plane
## respawn, target popping, glider descent from the rafter tower, and the
## health system: contact damage, i-frames, death state, checkpoint bloom
## and respawn at the last checkpoint (issue #8).

var t: float = 0.0
var player: Node = null
var stage: int = 0
var failed: bool = false
var _shoot_frames: int = 0
var _glide_t: float = -1.0


func _initialize() -> void:
	var packed: PackedScene = load("res://scenes/levels/entrance_conservatory.tscn")
	if packed == null:
		print("FAIL: could not load level scene")
		failed = true
		quit(1)
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	current_scene = scene
	physics_frame.connect(_tick)


func _tick() -> void:
	t += 1.0 / 60.0
	if player == null:
		var players := get_nodes_in_group("player")
		if players.size() > 0:
			player = players[0]
		return

	match stage:
		0:  # Settle on the floor
			if t > 0.5:
				_check(player.is_on_floor(), "player grounded at spawn")
				_check(absf(player.global_position.z - 6.0) < 1.0,
						"player settled at spawn (z=%f)" % player.global_position.z)
				Input.action_press("move_forward")
				stage = 1
		1:  # Walk forward for 2.5s
			if t > 3.0:
				Input.action_release("move_forward")
				_check(player.global_position.z < 0.0,
						"player walked forward (z=%f)" % player.global_position.z)
				stage = 2
		2:  # Jump
			if t > 3.2:
				Input.action_press("jump")
				stage = 3
		3:
			if t > 3.6:
				Input.action_release("jump")
				_check(player.global_position.y > 0.3,
						"player jumped (y=%f)" % player.global_position.y)
				stage = 4
		4:  # Move to the open target range
			if t > 3.8:
				player.global_position = Vector3(0, 1.0, -62.5)
				player.velocity = Vector3.ZERO
				stage = 5
		5:  # Fire three seeds at slightly different pitches at Target2
			if t > 4.0:
				player._camera_pivot.rotation.x = -0.08
				Input.action_press("shoot")
				stage = 6
				_shoot_frames = 0
		6:
			Input.action_release("shoot")
			_shoot_frames += 1
			var after: int = _count_projectiles()
			if after > 0:
				_check(true, "seed projectile spawned (%d in flight)" % after)
				stage = 7
			elif _shoot_frames > 30:
				_check(false, "seed projectile spawned (0 in flight after 30 frames)")
				stage = 7
		7:
			if t > 4.6:
				player._camera_pivot.rotation.x = -0.12
				Input.action_press("shoot")
				stage = 8
		8:
			Input.action_release("shoot")
			if t > 4.7:
				player._camera_pivot.rotation.x = -0.16
				Input.action_press("shoot")
				stage = 9
		9:
			Input.action_release("shoot")
			if t > 5.8:
				var level: Node = current_scene
				var popped: int = level._targets_popped
				_check(popped > 0, "a target bud popped from seed fire (%d popped)" % popped)
				stage = 10
		10:  # Kill plane: drop into the zone below the world
			if t > 6.0:
				player.global_position = Vector3(0, -12, 6)
				stage = 11
		11:
			if t > 6.8:
				_check(player.global_position.y > -2.0,
						"kill plane respawned player (y=%f)" % player.global_position.y)
				_check(player.current_health == player.max_health,
						"health restored on respawn")
				player.global_position = Vector3(0, 7.0, -41)
				player.velocity = Vector3.ZERO
				stage = 12
		12:  # Settle on the tower platform
			if t > 7.4:
				_check(player.is_on_floor(),
						"player standing on rafter tower platform (y=%f)" % player.global_position.y)
				Input.action_press("move_forward")
				stage = 13
		13:  # Walk off the edge, then deploy the glider (physical G key)
			if not player.is_on_floor():
				_press_key(KEY_G, true)
				_glide_t = t
				stage = 14
			elif t > 9.0:
				_check(false, "player never left the tower platform")
				stage = 16
		14:
			_press_key(KEY_G, false)
			if t > _glide_t + 1.0:
				_check(player.global_position.y > 4.0,
						"glider slows descent (y=%f after 1s of glide)" % player.global_position.y)
				_check(player.global_position.z < -43.5,
						"glider carried player forward (z=%f)" % player.global_position.z)
				Input.action_release("move_forward")
				stage = 16
		16:  # Let it land, then start health-system checks (issue #8)
			if t > 11.0:
				_check(player.is_on_floor(),
						"player landed safely after glide (y=%f)" % player.global_position.y)
				## Bloom the arena checkpoint by standing in its trigger
				player.global_position = Vector3(0, 1.0, -76)
				player.velocity = Vector3.ZERO
				stage = 17
		17:  # Checkpoint activation + first contact hit
			if t > 11.8:
				var level: Node = current_scene
				_check(level._active_checkpoint != null
						and level._active_checkpoint.is_active,
						"arena checkpoint bloomed on player touch")
				var hud: Node = level.get_node_or_null("UI/HealthHUD")
				_check(hud != null and hud._max_health == player.max_health,
						"health HUD present and tracking max health")
				## Isolated damage-test spot so no grub interferes
				player.global_position = Vector3(12, 1.0, 0)
				player.velocity = Vector3.ZERO
				player.take_damage(1, player.global_position + Vector3.FORWARD)
				_check(player.current_health == player.max_health - 1,
						"contact damage registered (%d/%d)"
						% [player.current_health, player.max_health])
				_check(hud._health == player.current_health,
						"health HUD mirrors player health")
				_check(player._hurt_timer > 0.0,
						"i-frames active after hit")
				stage = 18
		18:  # i-frames: immediate second hit must be ignored
			player.take_damage(1, player.global_position)
			if t > 12.2:
				_check(player.current_health == player.max_health - 1,
						"i-frames blocked immediate second hit")
				stage = 19
		19:  # Lethal damage -> death state
			if t > 12.4:
				player._hurt_timer = 0.0
				player.take_damage(5, player.global_position)
				_check(player.current_health == 0,
						"health reached zero on lethal hit")
				_check(player.is_dead,
						"player entered death state (input disabled, dissolving)")
				stage = 20
		20:  # Respawn at the last checkpoint
			if t > 14.4:  # death at ~12.4 + RESPAWN_DELAY 1.2
				_check(not player.is_dead,
						"player respawned after death")
				_check(player.current_health == player.max_health,
						"health restored on death respawn")
				_check(absf(player.global_position.z + 76.0) < 1.0
						and player.global_position.y > -0.5,
						"respawned at last checkpoint (pos=%s)"
						% player.global_position)
				stage = 21
		21:  # Wrap up
			if t > 14.6:
				print("SMOKE TEST %s" % ("PASSED" if not failed else "FAILED"))
				quit(0 if not failed else 1)


func _count_projectiles() -> int:
	return _count_rigid(root)


func _count_rigid(node: Node) -> int:
	var count := 0
	if node is RigidBody3D:
		count += 1
	for child in node.get_children():
		count += _count_rigid(child)
	return count


func _press_key(keycode: Key, pressed: bool) -> void:
	## The controller's _input listens for physical key events (e.g. G for
	## the glider), so synthetic InputEventKey events are required.
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.physical_keycode = keycode
	ev.pressed = pressed
	Input.parse_input_event(ev)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: " + label)
	else:
		print("FAIL: " + label)
		failed = true
