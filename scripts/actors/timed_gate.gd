class_name TimedGate
extends StaticBody2D
## A tall security gate that is open until its controller (a floor plate
## emitting state_changed) is pressed. From the press it stays open for
## `hold_open` seconds, flashing and ticking in the last `warn_time`, then rolls
## shut in `roll_time`. Pressing the plate again reopens it and restarts the
## clock. A bar on the header drains with the time left, so the clock reads
## without any text. An obstruction sensor stops the bar above the cat's head
## instead of crushing it, so the gate only wins against a cat that is late.
## Origin = the middle of the base. Taller than a double jump can clear.

signal state_changed(open: bool)
signal armed

@export var controller: NodePath
@export var height_tiles := 7
@export var width := 20.0
@export var hold_open := 3.5
@export var warn_time := 1.0
@export var roll_time := 0.5

## True while the gate lets the cat through (open, or the clock still running).
var open := true
var time_left := 0.0
var _armed := false
var _lift := 1.0  # 1 rolled up .. 0 shut
var _shape := RectangleShape2D.new()
var _cs := CollisionShape2D.new()
var _sensor := Area2D.new()
var _tick := 0.0
var _t := 0.0
var _slammed := false


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	var h := height_tiles * 32.0
	_shape.size = Vector2(width, 1.0)
	_cs.shape = _shape
	_cs.disabled = true
	add_child(_cs)
	_sensor.collision_layer = 0
	_sensor.collision_mask = 2
	var scs := CollisionShape2D.new()
	var sr := RectangleShape2D.new()
	sr.size = Vector2(width + 12.0, h)
	scs.shape = sr
	scs.position = Vector2(0, -h / 2.0)
	_sensor.add_child(scs)
	add_child(_sensor)
	var c := get_node_or_null(controller)
	if c and c.has_signal("state_changed"):
		c.state_changed.connect(_on_controller)
	queue_redraw()


func _on_controller(active: bool) -> void:
	if not active:
		return
	_armed = true
	open = true
	_slammed = false
	time_left = hold_open
	armed.emit()
	state_changed.emit(true)


func is_shut() -> bool:
	return _lift <= 0.0


func _physics_process(delta: float) -> void:
	_t += delta
	var h := height_tiles * 32.0
	if _armed and time_left > 0.0:
		time_left -= delta
		if time_left <= warn_time:
			_tick -= delta
			if _tick <= 0.0:
				_tick = 0.35
				Sfx.play(self, "pickup", -16.0, 1.9)
		if time_left <= 0.0:
			open = false
			_armed = false
			state_changed.emit(false)
	var want := 1.0 if open else 0.0
	var lift := move_toward(_lift, want, delta / roll_time)
	if lift < _lift:
		# Closing: hold the bar above a cat standing in the doorway.
		var bar_y := -h + h * (1.0 - lift)
		for b in _sensor.get_overlapping_bodies():
			if b is Cat:
				var c := b as Cat
				var top := c.global_position.y - global_position.y - (14.0 if c.crouched else 26.0)
				if bar_y > top - 4.0:
					lift = _lift
	if lift != _lift:
		_lift = lift
		var shown := h * (1.0 - _lift)
		_shape.size.y = maxf(shown, 1.0)
		_cs.position.y = -h + shown / 2.0
		_cs.disabled = shown < 2.0
	if _lift <= 0.0 and not _slammed:
		_slammed = true
		Sfx.play(self, "door", -6.0, 0.7)
	queue_redraw()


func _draw() -> void:
	var h := height_tiles * 32.0
	var w := width
	var top := -h
	var warn := _armed and time_left <= warn_time
	var flash := int(_t * 8.0) % 2 == 0
	# Header box and the countdown bar.
	draw_rect(Rect2(-w / 2.0 - 6, top - 14, w + 12, 16), Color("10121f"))
	draw_rect(Rect2(-w / 2.0 - 5, top - 13, w + 10, 14), Color("354655"))
	draw_rect(Rect2(-w / 2.0 - 5, top - 13, w + 10, 2), Color("536a74"))
	var frac := clampf(time_left / hold_open, 0.0, 1.0) if _armed else (1.0 if open else 0.0)
	var lamp := FXPalette.INDICATOR
	if not open:
		lamp = FXPalette.SODIUM
	elif warn:
		lamp = FXPalette.SODIUM if flash else Color("5a3a1a")
	draw_rect(Rect2(-w / 2.0 - 2, top - 9, w + 4, 6), Color("141a2c"))
	draw_rect(Rect2(-w / 2.0 - 1, top - 8, (w + 2) * frac, 4), lamp)
	# Chain-link panel, hung from the header and rolled up into it.
	var shown := h * (1.0 - _lift)
	if shown > 1.0:
		draw_rect(Rect2(-w / 2.0, top, w, shown), Color(0.08, 0.10, 0.16, 0.85))
		var y := top
		while y < top + shown:
			var seg := minf(8.0, top + shown - y)
			draw_line(Vector2(-w / 2.0, y), Vector2(w / 2.0, y + seg), Color(0.55, 0.64, 0.68, 0.8), 1.0)
			draw_line(Vector2(w / 2.0, y), Vector2(-w / 2.0, y + seg), Color(0.40, 0.48, 0.55, 0.8), 1.0)
			y += 8.0
		var bar := Color("d07a26") if not warn or flash else Color("ffd66e")
		draw_rect(Rect2(-w / 2.0 - 2, top + shown - 5, w + 4, 5), bar)
		draw_rect(Rect2(-w / 2.0 - 2, top + shown - 5, w + 4, 1), Color("ffd66e"))
	# Posts.
	draw_rect(Rect2(-w / 2.0 - 5, top, 4, h), Color("2a4658"))
	draw_rect(Rect2(w / 2.0 + 1, top, 4, h), Color("2a4658"))
	draw_rect(Rect2(-w / 2.0 - 5, top, 1, h), Color("5b7280"))
	draw_rect(Rect2(w / 2.0 + 1, top, 1, h), Color("5b7280"))
