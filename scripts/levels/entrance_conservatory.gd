class_name EntranceConservatory
extends Node3D
## Entrance Conservatory — the tutorial level (issue #7).
##
## A linear greenhouse wing that teaches movement, jumping, gliding, and
## shooting before the Orchid Tropics open. This script owns:
## - Spawn point + respawn logic (death or kill-plane returns the player
##   to the start, freshly bloomed)
## - Level boundary backstop: the KillZone Area3D below the floor
## - Tutorial progress prints (targets popped, grubs purged)
##
## The floor is continuous and the perimeter walls are physical, so falling
## out of the world is impossible; the kill zone exists as a safety net and
## to satisfy the level-boundary requirement for any future gaps.

## Seconds to wait after death before respawning (lets the hit flash read)
const RESPAWN_DELAY: float = 1.2

@onready var _player: FirstPersonController = $Player
@onready var _spawn_point: Marker3D = $SpawnPoint
@onready var _kill_zone: Area3D = $KillZone

## Tutorial progress tracking (prints to console; HUD hooks come later)
var _targets_total: int = 0
var _targets_popped: int = 0
var _grubs_total: int = 0
var _grubs_purged: int = 0
var _respawn_pending: bool = false


func _ready() -> void:
	_player.player_died.connect(_on_player_died)
	_kill_zone.body_entered.connect(_on_kill_zone_body_entered)

	## Count shootable targets and hook their destruction signal
	for target in get_tree().get_nodes_in_group("targets"):
		if target is TargetDummy:
			_targets_total += 1
			target.target_destroyed.connect(_on_target_destroyed)

	## Count grubs for the combat encounter progress
	for node in get_children():
		_count_grubs(node)

	print("=== Entrance Conservatory ===")
	print("Tutorial wing: %d targets, %d grubs on watch" % [
			_targets_total, _grubs_total])


func _count_grubs(node: Node) -> void:
	## Find BlightedGrub instances anywhere in the tree (they emit `died`)
	if node is BlightedGrub:
		_grubs_total += 1
		node.died.connect(_on_grub_died)
	for child in node.get_children():
		_count_grubs(child)


func _on_player_died() -> void:
	if _respawn_pending:
		return
	_respawn_pending = true
	print("[Level] Player purged by the Blight — respawning...")
	await get_tree().create_timer(RESPAWN_DELAY).timeout
	_respawn()
	_respawn_pending = false


func _on_kill_zone_body_entered(body: Node3D) -> void:
	## Safety net below the world — respawn immediately
	if body == _player:
		print("[Level] Player left the world bounds — respawning...")
		_respawn()


func _respawn() -> void:
	## Back to the start, health restored, velocity zeroed
	_player.respawn_at(_spawn_point.global_position)


func _on_target_destroyed(_target: TargetDummy) -> void:
	_targets_popped += 1
	print("[Level] Target popped (%d/%d)" % [_targets_popped, _targets_total])


func _on_grub_died(_grub: BlightedGrub) -> void:
	_grubs_purged += 1
	if _grubs_purged >= _grubs_total:
		print("[Level] The soil breathes easier — all grubs purged!")
	else:
		print("[Level] Grub purged (%d/%d)" % [_grubs_purged, _grubs_total])
