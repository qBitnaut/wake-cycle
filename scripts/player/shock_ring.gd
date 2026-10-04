class_name ShockRing
extends Node2D
## Placeholder expanding ring for shockwaves. Real FX can listen to Cat.shockwave.

var radius := 36.0
var color := Color.WHITE
var _t := 0.0


static func spawn(parent: Node, pos: Vector2, r: float, c: Color) -> void:
	var ring := ShockRing.new()
	ring.radius = r
	ring.color = c
	ring.global_position = pos
	ring.z_index = 20
	parent.add_child(ring)


func _process(delta: float) -> void:
	_t += delta / 0.28
	if _t >= 1.0:
		queue_free()
	queue_redraw()


func _draw() -> void:
	var r := radius * ease(_t, 0.4)
	var c := color
	c.a = 1.0 - _t
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, c, 2.0)
	draw_arc(Vector2.ZERO, r * 0.7, 0.0, TAU, 32, Color(c, c.a * 0.5), 1.0)
