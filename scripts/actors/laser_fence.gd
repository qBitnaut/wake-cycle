class_name LaserFence
extends Hazard
## Vertical laser fence. Timed on/off, and/or switched off while a controller
## (floor plate or shock switch emitting state_changed) is active. Origin = base post.
##
## The beam is a LaserBeam (unshaded HDR strip plus a red light); the posts are
## hazard-ramp tile slices. Red means hostile, so the beam is the only red.

const POST_H := 10.0

@export var height_tiles := 3
@export var timed := true
@export var on_time := 1.6
@export var off_time := 1.4
@export var start_offset := 0.0
@export var controller: NodePath

var _t := 0.0
var _ctrl_active := false
var _shape := RectangleShape2D.new()
var _beam: LaserBeam


func _ready() -> void:
	super()
	kill = false
	phase_through = true
	_t = start_offset
	var h := height_tiles * 32.0
	var cs := CollisionShape2D.new()
	_shape.size = Vector2(6, h - 2.0 * POST_H)
	cs.shape = _shape
	cs.position = Vector2(0, -h / 2.0)
	add_child(cs)
	var bottom := TileArt.sprite("hazard", TileArt.BEVEL, Rect2i(0, 0, 32, int(POST_H)))
	bottom.position = Vector2(-16, -POST_H)
	add_child(bottom)
	var top := TileArt.sprite("hazard", TileArt.BEVEL, Rect2i(0, 32 - int(POST_H), 32, int(POST_H)))
	top.position = Vector2(-16, -h)
	add_child(top)
	_beam = LaserBeam.new()
	_beam.vertical = true
	_beam.length = h - 2.0 * POST_H
	_beam.jitter = true
	_beam.position = Vector2(0, -POST_H)
	add_child(_beam)
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
	# Just before a timed beam fires it flickers faintly, as a warning.
	var warn := false
	if timed and not _ctrl_active and not active:
		warn = fmod(_t, on_time + off_time) > on_time + off_time - 0.35
	var show := active or (warn and int(_t * 24.0) % 2 == 0)
	_beam.set_on(show)
	_beam.modulate.a = 1.0 if active else 0.35
