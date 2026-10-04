class_name ScreenShake
extends Node
## Camera shake in whole pixels (so the pixel art never smears). Add it as a
## child of a Camera2D, or let ScreenShake.shake_at() find or create one.
##
##     ScreenShake.shake_at(self, 0.6)          # from anywhere in the tree
##     $Camera2D/ScreenShake.shake(1.0, 0.4)    # direct
##     some_signal.connect($Camera2D/ScreenShake.shake.bind(0.5, 0.3))
##
## Trauma model: strength stacks up to 1 and decays; offset = trauma^2.

@export var camera: Camera2D
@export var max_offset := Vector2(5, 4)
@export var frequency := 28.0

var _trauma := 0.0
var _decay := 3.0
var _t := 0.0
var _seed := Vector2(randf() * 100.0, randf() * 100.0)
var _base_offset := Vector2.ZERO


func _ready() -> void:
	if camera == null and get_parent() is Camera2D:
		camera = get_parent()
	if camera:
		_base_offset = camera.offset


## Shake the camera of `node`'s viewport. Creates a ScreenShake on the camera
## the first time. Safe to call when there is no camera (does nothing).
static func shake_at(node: Node, strength := 0.5, duration := 0.35) -> void:
	var cam := node.get_viewport().get_camera_2d()
	if cam == null:
		return
	var s: ScreenShake = null
	for c in cam.get_children():
		if c is ScreenShake:
			s = c
			break
	if s == null:
		s = ScreenShake.new()
		s.name = "ScreenShake"
		s.camera = cam
		cam.add_child(s)
	s.shake(strength, duration)


## Add `strength` (0..1) of trauma that dies away over about `duration` s.
func shake(strength := 0.5, duration := 0.35) -> void:
	_trauma = clampf(_trauma + strength, 0.0, 1.0)
	_decay = 1.0 / maxf(duration, 0.05)


func _process(delta: float) -> void:
	if camera == null:
		return
	if _trauma <= 0.0:
		camera.offset = _base_offset
		return
	_t += delta
	_trauma = maxf(_trauma - _decay * delta, 0.0)
	var k := _trauma * _trauma
	var nx := sin(_t * frequency + _seed.x) * 0.6 + sin(_t * frequency * 2.3 + _seed.y) * 0.4
	var ny := sin(_t * frequency * 1.1 + _seed.y) * 0.6 + sin(_t * frequency * 1.9 + _seed.x) * 0.4
	camera.offset = _base_offset + Vector2(roundf(nx * max_offset.x * k), roundf(ny * max_offset.y * k))
