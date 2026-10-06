class_name Shutter
extends StaticBody2D
## A roller shutter across the route. It is shut until its controller (a floor
## plate or switch emitting state_changed(active)) is active, then rolls up
## into the header; it rolls back down when the controller lets go. The
## header is drawn above the opening, so the shutter looks like part of the
## wall. Origin = the middle of the base. Pair it with a ceiling over the
## opening so it cannot be hopped over.

signal state_changed(open: bool)

@export var controller: NodePath
@export var height_tiles := 3
@export var width := 20.0
@export var roll_time := 0.6

var open := false
var _lift := 0.0  # 0 shut .. 1 fully rolled up
var _drawn_open := false
var _shape := RectangleShape2D.new()
var _cs := CollisionShape2D.new()


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	_shape.size = Vector2(width, height_tiles * 32.0)
	_cs.shape = _shape
	_cs.position = Vector2(0, -height_tiles * 16.0)
	add_child(_cs)
	var c := get_node_or_null(controller)
	if c and c.has_signal("state_changed"):
		c.state_changed.connect(_on_controller)


func _on_controller(active: bool) -> void:
	if active == open:
		return
	open = active
	Sfx.play(self, "shutter_open")
	state_changed.emit(open)


func _physics_process(delta: float) -> void:
	var target := 1.0 if open else 0.0
	var before := _lift
	_lift = move_toward(_lift, target, delta / roll_time)
	if _lift != before or open != _drawn_open:
		_drawn_open = open
		var h := height_tiles * 32.0 * (1.0 - _lift)
		_shape.size.y = maxf(h, 0.01)
		_cs.position.y = -h / 2.0
		_cs.disabled = h < 2.0
		queue_redraw()


func _draw() -> void:
	var h := height_tiles * 32.0
	var w := width
	var top := -h
	# Header box above the opening (always there).
	draw_rect(Rect2(-w / 2.0 - 4, top - 10, w + 8, 12), Color("10121f"))
	draw_rect(Rect2(-w / 2.0 - 3, top - 9, w + 6, 10), Color("354655"))
	draw_rect(Rect2(-w / 2.0 - 3, top - 9, w + 6, 2), Color("536a74"))
	# Status lamp on the header: amber while shut, muted aqua once open.
	var lamp := FXPalette.INDICATOR if open else FXPalette.SODIUM
	draw_rect(Rect2(-3, top - 7, 6, 4), Color("141a2c"))
	draw_rect(Rect2(-2, top - 6, 4, 2), lamp)
	# Slats: shutter lowered by (1 - lift), rolled up part hidden in the header.
	var shown := h * (1.0 - _lift)
	if shown > 1.0:
		draw_rect(Rect2(-w / 2.0, top, w, shown), Color("141a2c"))
		var y := top
		var i := 0
		while y < top + shown:
			var sh := minf(6.0, top + shown - y)
			draw_rect(Rect2(-w / 2.0 + 1, y + 1, w - 2, maxf(sh - 1.0, 1.0)), Color("2a4658") if i % 2 == 0 else Color("1c2c3b"))
			y += 6.0
			i += 1
		draw_rect(Rect2(-w / 2.0, top + shown - 3, w, 3), Color("d07a26"))  # hazard-amber bottom bar
	# Side rails.
	draw_rect(Rect2(-w / 2.0 - 3, top, 3, h), Color("1c2c3b"))
	draw_rect(Rect2(w / 2.0, top, 3, h), Color("1c2c3b"))
