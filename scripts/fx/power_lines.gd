@tool
class_name PowerLines
extends Node2D
## Wooden utility poles along the street and the wires between them, sagging
## in shallow catenaries, wet and catching the sun along their tops. The last
## span can run down to a house (a service drop). Drawn in code at 1 px.
## Origin = world origin; poles are the x of each pole's foot (on `foot_y`).

@export var poles: Array[float] = []:
	set(v):
		poles = v
		queue_redraw()
@export var foot_y := 300.0
@export var pole_height := 196.0
## Wire heights below the pole top, px (one wire per entry).
@export var wires: Array[float] = [8.0, 18.0]:
	set(v):
		wires = v
		queue_redraw()
@export var sag := 14.0
## Optional end point for a service drop from the last pole (world px).
@export var drop_to := Vector2.ZERO
@export var wire_color := Color("3a3448")
@export var shine := Color("c8d4e4")

const WOOD := Color("5a4034")
const WOOD_LIT := Color("8c6545")
const WOOD_INK := Color("2e2230")
const ARM := Color("4a3328")


## Where a wire hangs at world x (for birds and drips), or NAN outside the line.
func wire_y(x: float, wire := 0) -> float:
	for i in poles.size() - 1:
		var a := poles[i]
		var b := poles[i + 1]
		if x >= a and x <= b:
			var t := (x - a) / (b - a)
			var top := foot_y - pole_height + wires[wire]
			return top + sag * 4.0 * t * (1.0 - t)
	return NAN


func _draw() -> void:
	var top := foot_y - pole_height
	for x in poles:
		draw_rect(Rect2(x - 3, top, 6, pole_height), WOOD)
		draw_rect(Rect2(x + 2, top, 1, pole_height), WOOD_LIT)
		draw_rect(Rect2(x - 3, top, 1, pole_height), WOOD_INK)
		draw_rect(Rect2(x - 18, top + 4, 36, 4), ARM)
		draw_rect(Rect2(x - 18, top + 4, 36, 1), WOOD_LIT)
		for k in [-14, -6, 6, 14]:
			draw_rect(Rect2(x + k - 1, top, 2, 4), Color("d8dce8"))
		draw_rect(Rect2(x - 4, top - 2, 8, 2), WOOD_INK)
	for w in wires.size():
		var y0 := top + wires[w]
		for i in poles.size() - 1:
			_span(Vector2(poles[i], y0), Vector2(poles[i + 1], y0), sag)
	if drop_to != Vector2.ZERO and poles.size() > 0:
		_span(Vector2(poles[-1], top + wires[0]), drop_to, sag * 0.5)


func _span(a: Vector2, b: Vector2, s: float) -> void:
	var n := int(absf(b.x - a.x))
	var prev := a
	for i in range(1, n + 1):
		var t := float(i) / n
		var p := Vector2(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t + s * 4.0 * t * (1.0 - t)).floor()
		draw_rect(Rect2(p, Vector2.ONE), wire_color)
		if int(p.x) % 7 < 3:
			draw_rect(Rect2(p + Vector2(0, -1), Vector2.ONE), Color(shine, 0.55))
		if absf(p.y - prev.y) > 1.0:
			draw_rect(Rect2(Vector2(p.x, minf(p.y, prev.y)), Vector2(1, absf(p.y - prev.y))), wire_color)
		prev = p
