class_name LaserFence
extends Hazard
## Vertical laser fence. Timed on/off, and/or switched off while a controller
## (floor plate or shock switch emitting state_changed) is active. Origin = base post.

@export var height_tiles := 3
@export var timed := true
@export var on_time := 1.6
@export var off_time := 1.4
@export var start_offset := 0.0
@export var controller: NodePath

var _t := 0.0
var _ctrl_active := false
var _shape := RectangleShape2D.new()


func _ready() -> void:
	super()
	kill = false
	phase_through = true
	_t = start_offset
	var cs := CollisionShape2D.new()
	_shape.size = Vector2(4, height_tiles * 18.0 - 8.0)
	cs.shape = _shape
	cs.position = Vector2(0, -height_tiles * 18.0 / 2.0)
	add_child(cs)
	var c := get_node_or_null(controller)
	if c and c.has_signal("state_changed"):
		c.state_changed.connect(func(a: bool): _ctrl_active = a)


func _beam_on() -> bool:
	if _ctrl_active:
		return false
	if timed:
		return fmod(_t, on_time + off_time) < on_time
	return true


func _process(delta: float) -> void:
	_t += delta
	active = _beam_on()
	queue_redraw()


func _draw() -> void:
	var h := height_tiles * 18.0
	var post := Color("8fa0b0")
	draw_rect(Rect2(-3, -6, 6, 6), post)
	draw_rect(Rect2(-3, -h, 6, 6), post)
	var warn := false
	if timed and not _ctrl_active and not active:
		warn = fmod(_t, on_time + off_time) > on_time + off_time - 0.35
	draw_rect(Rect2(-1, -h + 6, 2, 3), Color("ff3b3b"))
	draw_rect(Rect2(-1, -9, 2, 3), Color("ff3b3b"))
	if active:
		var j := int(_t * 30.0) % 2
		draw_rect(Rect2(-1 + j, -h + 6, 2, h - 12), Color("ff5555"))
		draw_rect(Rect2(-3 + j, -h + 6, 6, h - 12), Color(1, 0.2, 0.2, 0.25))
	elif warn and int(_t * 24.0) % 2 == 0:
		draw_rect(Rect2(-1, -h + 6, 1, h - 12), Color(1, 0.4, 0.4, 0.5))
