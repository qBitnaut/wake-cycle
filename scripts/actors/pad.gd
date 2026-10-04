class_name Pad
extends Area2D
## Enhancement pad: step on it to gain a timed nano power (or, for the debug /
## story stand-in, to unlock the shockwave). Re-usable after a cooldown.

signal activated(power: int)

const UNLOCK_SHOCKWAVE := 99

@export_enum("Surge:1", "Spring:2", "Phase:3", "Impact:4", "Unlock Shockwave:99") var power := 1
@export var duration := 10.0
@export var cooldown := 3.0

var _cd := 0.0
var _t := 0.0


func _ready() -> void:
	collision_layer = 32
	collision_mask = 2
	body_entered.connect(_on_body)


func _color() -> Color:
	return NanoPalette.SHOCKWAVE if power == UNLOCK_SHOCKWAVE else NanoPalette.color_of(power)


func _on_body(body: Node) -> void:
	if _cd > 0.0 or not body is Cat:
		return
	if power == UNLOCK_SHOCKWAVE:
		if GameState.shockwave_unlocked:
			return
		GameState.shockwave_unlocked = true
		_cd = 1e9
	else:
		GameState.grant_power(power, duration)
		_cd = cooldown
	Sfx.play(self, "power_up")
	activated.emit(power)


func _process(delta: float) -> void:
	_t += delta
	if _cd > 0.0 and _cd < 1e8:
		_cd -= delta
		if _cd <= 0.0:
			for b in get_overlapping_bodies():
				_on_body(b)
	queue_redraw()


func _draw() -> void:
	var c := _color()
	var ready := _cd <= 0.0
	var a := 1.0 if ready else 0.3
	var pulse := 0.5 + 0.5 * sin(_t * 5.0)
	draw_rect(Rect2(-11, -3, 22, 3), Color(c, a))
	draw_rect(Rect2(-9, -4, 18, 1), Color(c.lightened(0.4), a))
	if ready:
		draw_rect(Rect2(-9, -22, 18, 18), Color(c, 0.10 + 0.08 * pulse))
	var y := -12.0 - 2.0 * pulse
	var w := Color(1, 1, 1, a)
	match power:
		NanoPalette.Power.SURGE:
			for x in [-4.0, 1.0]:
				draw_polyline(PackedVector2Array([Vector2(x, y - 4), Vector2(x + 3, y), Vector2(x, y + 4)]), w, 1.0)
		NanoPalette.Power.SPRING:
			draw_polyline(PackedVector2Array([Vector2(-4, y + 2), Vector2(0, y - 3), Vector2(4, y + 2)]), w, 1.0)
		NanoPalette.Power.PHASE:
			draw_dashed_line(Vector2(-5, y), Vector2(5, y), w, 1.0, 2.0)
			draw_dashed_line(Vector2(-5, y + 3), Vector2(5, y + 3), w, 1.0, 2.0)
		NanoPalette.Power.IMPACT:
			draw_polyline(PackedVector2Array([Vector2(-4, y - 2), Vector2(0, y + 3), Vector2(4, y - 2)]), w, 1.0)
		UNLOCK_SHOCKWAVE:
			draw_arc(Vector2(0, y), 3.0, 0.0, TAU, 12, w, 1.0)
			draw_arc(Vector2(0, y), 6.0, 0.0, TAU, 16, w, 1.0)
