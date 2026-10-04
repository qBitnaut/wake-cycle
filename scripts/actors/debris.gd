class_name Debris
extends Node2D
## Tiny placeholder particles for breaking things.

var _parts: Array = []
var _color := Color.WHITE
var _t := 0.0


static func burst(parent: Node, pos: Vector2, color: Color, count := 8) -> void:
	var d := Debris.new()
	d._color = color
	d.global_position = pos
	d.z_index = 15
	for i in count:
		d._parts.append([Vector2.ZERO, Vector2(randf_range(-124, 124), randf_range(-231, -53))])
	parent.add_child(d)


func _process(delta: float) -> void:
	_t += delta
	for p in _parts:
		p[1].y += 889.0 * delta
		p[0] += p[1] * delta
	if _t > 0.7:
		queue_free()
	queue_redraw()


func _draw() -> void:
	for p in _parts:
		draw_rect(Rect2(p[0].round(), Vector2(4, 4)), Color(_color, 1.0 - _t / 0.7))
