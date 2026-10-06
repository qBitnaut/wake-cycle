class_name ScorePopup
extends Node2D
## "+200" floating up from where something was earned, then fading.

const FONT := preload("res://assets/fonts/monogram.ttf")

var text := "+100"
var color := Color(1.0, 0.82, 0.25)
var life := 0.95
var rise := 26.0
var _t := 0.0


static func spawn(parent: Node, pos: Vector2, label: String, col := Color(1.0, 0.82, 0.25)) -> ScorePopup:
	var p := ScorePopup.new()
	p.text = label
	p.color = col
	p.z_index = 60
	KitUtil.add_at(parent, p, pos)
	return p


func _process(delta: float) -> void:
	_t += delta
	if _t >= life:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var k := clampf(_t / life, 0.0, 1.0)
	var y := -rise * (1.0 - pow(1.0 - k, 3.0))
	var a := 1.0 if k < 0.65 else 1.0 - (k - 0.65) / 0.35
	var pos := Vector2(-24.0, roundf(y))
	var ink := Color(0.09, 0.09, 0.19, a)
	for o in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		draw_string(FONT, pos + o, text, HORIZONTAL_ALIGNMENT_CENTER, 48.0, 16, ink)
	draw_string(FONT, pos, text, HORIZONTAL_ALIGNMENT_CENTER, 48.0, 16, Color(color.r * 1.4, color.g * 1.4, color.b * 1.4, a))
