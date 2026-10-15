class_name HealthHUD
extends Control
## Health HUD for the player (issue #8).
##
## Three layers of "how am I doing" feedback, ordered by urgency:
## 1. Hearts (bottom-left) — exact hit count, pops when it changes
## 2. Damage vignette (edges) — grows as health drops, pulses at 1 heart
## 3. Heartbeat audio — only at 1 heart, so critical health is felt
##
## Also flashes short messages ("Checkpoint Bloomed", "You withered...") so
## death/respawn feedback reads even with the camera mid-shake.
##
## The HUD finds the player via the "player" group, so it works in any
## level scene without wiring — drop it under a CanvasLayer and done.
##
## Feel goals (DESIGN.md): garden-toned feedback — warm rose hearts, a
## bruised-crimson vignette. Never horror-red, never grim.

## Heart layout (pixels)
const HEART_SIZE: float = 36.0
const HEART_SPACING: float = 42.0

## Colors — garden palette, not gore
const HEART_FULL := Color(0.94, 0.38, 0.45)      # warm rose
const HEART_FULL_GLOW := Color(1.0, 0.62, 0.6)   # top highlight
const HEART_EMPTY := Color(0.16, 0.2, 0.17, 0.6) # dim husk
const HEART_OUTLINE := Color(0.08, 0.1, 0.09, 0.8)

@onready var _vignette: ColorRect = $Vignette
@onready var _hearts: Control = $Hearts
@onready var _death_label: Label = $DeathLabel
@onready var _checkpoint_label: Label = $CheckpointLabel
@onready var _heartbeat: AudioStreamPlayer = $Heartbeat

var _player: FirstPersonController
var _health: int = -1
var _max_health: int = -1
var _crit_pulse_time: float = 0.0
var _heartbeat_cooldown: float = 0.0

## Extra vignette intensity from a damage spike (decays back to base)
var _vignette_spike: float = 0.0

var _heart_pop_tween: Tween

## Health from the previous change, used to detect damage vs heal
var _previous_health: int = -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_death_label.modulate.a = 0.0
	_checkpoint_label.modulate.a = 0.0

	## Draw the hearts inside the child control (root stays full-rect)
	_hearts.draw.connect(_draw_hearts)

	## Resolve the player (deferred: player may not be in the tree yet)
	_resolve_player.call_deferred()


func _resolve_player() -> void:
	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		_player = players[0] as FirstPersonController
		_player.health_changed.connect(_on_health_changed)
		_player.player_died.connect(_on_player_died)
		_on_health_changed(_player.current_health, _player.max_health)
	else:
		## Player not ready yet — retry next frame
		_resolve_player.call_deferred()


func _process(delta: float) -> void:
	if _max_health <= 0:
		return

	## Vignette: base = fraction of health missing; spikes on fresh damage
	_vignette_spike = maxf(_vignette_spike - 1.6 * delta, 0.0)
	var missing: float = 1.0 - float(_health) / float(_max_health)
	var intensity: float = missing * 0.6 + _vignette_spike

	## Critical (1 heart): vignette pulses + heartbeat thumps
	if _health == 1 and not _player.is_dead:
		_crit_pulse_time += delta
		intensity += 0.18 + 0.14 * sin(_crit_pulse_time * 4.0)
		_heartbeat_cooldown -= delta
		if _heartbeat_cooldown <= 0.0:
			_heartbeat.play()
			_heartbeat_cooldown = 0.85
		## Hearts pulse scale — urgent but small
		_hearts.scale = Vector2.ONE * (1.0 + 0.03 * sin(_crit_pulse_time * 6.0))
	else:
		_crit_pulse_time = 0.0
		_heartbeat_cooldown = 0.0
		## Reset the pulse scale, but don't fight an active heart-pop tween
		if _heart_pop_tween == null or not _heart_pop_tween.is_valid():
			_hearts.scale = Vector2.ONE

	var mat: ShaderMaterial = _vignette.material
	mat.set_shader_parameter("intensity", clampf(intensity, 0.0, 1.0))


func _on_health_changed(current: int, maximum: int) -> void:
	## Extra vignette kick when health went DOWN (fresh damage)
	if _previous_health >= 0 and current < _previous_health:
		_vignette_spike = 0.35
	_previous_health = current

	_health = current
	_max_health = maximum
	_heart_pop()

	## Clear the death message once we're alive again (respawn heals)
	if current > 0 and _death_label.modulate.a > 0.0:
		var fade := create_tween()
		fade.tween_property(_death_label, "modulate:a", 0.0, 0.4)

	_hearts.queue_redraw()


func _heart_pop() -> void:
	## Scale bounce on the hearts row; pivot at the row center.
	## Runs on damage AND heal — any change should feel like an event.
	var size: Vector2 = _hearts.size
	_hearts.pivot_offset = size / 2.0
	if _heart_pop_tween != null and _heart_pop_tween.is_valid():
		_heart_pop_tween.kill()
	_hearts.scale = Vector2.ONE * 1.25
	_heart_pop_tween = create_tween()
	_heart_pop_tween.tween_property(_hearts, "scale", Vector2.ONE, 0.25) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _on_player_died() -> void:
	## Death message fades in and stays until the respawn heals us
	_death_label.text = "You withered..."
	var tween := create_tween()
	tween.tween_property(_death_label, "modulate:a", 1.0, 0.4)


func show_checkpoint_message(message: String = "Checkpoint Bloomed") -> void:
	_checkpoint_label.text = message
	var tween := create_tween()
	tween.tween_property(_checkpoint_label, "modulate:a", 1.0, 0.2)
	tween.tween_interval(1.6)
	tween.tween_property(_checkpoint_label, "modulate:a", 0.0, 0.6)


func _draw_hearts() -> void:
	## Draw hearts as parametric heart-curve polygons, left to right.
	## Full hearts are filled rose with a highlight lobe; empty hearts are
	## dim husks with a faint outline.
	if _max_health <= 0:
		return

	var row_size: Vector2 = _hearts.size
	for i in _max_health:
		var center := Vector2(
				HEART_SPACING * 0.5 + HEART_SPACING * float(i),
				row_size.y - HEART_SIZE * 0.5)
		var filled: bool = i < _health

		var points := PackedVector2Array()
		var steps: int = 24
		for s in steps:
			var t := TAU * float(s) / float(steps)
			## Classic heart curve, flipped so it points down
			var p := Vector2(
					16.0 * pow(sin(t), 3.0),
					-(13.0 * cos(t) - 5.0 * cos(2.0 * t)
							- 2.0 * cos(3.0 * t) - cos(4.0 * t)))
			points.append(center + p * HEART_SIZE / 34.0)

		if filled:
			_hearts.draw_colored_polygon(points, HEART_FULL)
			## Highlight lobe: small circle offset up-left, subtle
			_hearts.draw_circle(center + Vector2(-6, -7) * HEART_SIZE / 34.0,
					4.0 * HEART_SIZE / 34.0, HEART_FULL_GLOW)
		else:
			_hearts.draw_colored_polygon(points, HEART_EMPTY)
		_hearts.draw_polyline(points + PackedVector2Array([points[0]]),
				HEART_OUTLINE, 1.5, true)
