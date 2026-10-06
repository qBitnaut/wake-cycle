class_name DockBot
extends Node2D
## An inactive robot on a charging dock: a hint of the "supervisor" idea, not a
## mechanic. It sleeps (dim body, a faint red visor) until the augmented cat
## walks within `react_range`, then its eyes flicker and settle on the colour of
## the cat's emitters, with a short chirp. Walk away and it dims again. It
## never moves, never hurts and has no collision. Origin = the dock floor.
## B' size: the 2/3 mech (assets/art_hd/robots/mech_23.png, tools/art/repixel.py),
## about 1.4 tiles tall, on a dock drawn to match.

signal reacted

const SHEET := preload("res://assets/art_hd/robots/mech_23.png")
const FRAME := Vector2i(64, 53)
const HALO := preload("res://assets/fx/halo.png")
const LIGHT_TEX := preload("res://assets/fx/light_soft.png")
## Visor and chest eye, in frame px.
const EYES := [Rect2(29, 15, 5, 2), Rect2(31, 23, 3, 2)]
const ASLEEP := Color(0.34, 0.37, 0.52)
const AWAKE := Color(0.62, 0.66, 0.84)

@export var react_range := 150.0
@export var face_cat := true

## 0 asleep .. 1 fully awake, and the eye colour it settled on (audit hooks).
var wake := 0.0
var eye_color := Color(FXPalette.LASER)
var has_reacted := false

var _cat: Cat
var _body: Sprite2D
var _eye_root: Node2D
var _eyes: Array[Polygon2D] = []
var _halo: Sprite2D
var _light: PointLight2D
var _flicker := 0.0
var _t := randf() * 5.0


func _ready() -> void:
	z_index = 1
	_body = Sprite2D.new()
	var at := AtlasTexture.new()
	at.atlas = SHEET
	at.region = Rect2(0, 0, FRAME.x, FRAME.y)
	_body.texture = at
	_body.centered = false
	_body.position = Vector2(-FRAME.x / 2.0, -FRAME.y)
	_body.self_modulate = ASLEEP
	add_child(_body)
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	add.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	# The eyes live under a node centred on the frame, so mirroring the body mirrors them.
	_eye_root = Node2D.new()
	_eye_root.position = _body.position + Vector2(FRAME.x / 2.0, 0)
	add_child(_eye_root)
	var solid := CanvasItemMaterial.new()
	solid.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	for r: Rect2 in EYES:
		var q := Rect2(r.position - Vector2(FRAME.x / 2.0, 0), r.size)
		var p := Polygon2D.new()
		p.polygon = PackedVector2Array([q.position, Vector2(q.end.x, q.position.y), q.end, Vector2(q.position.x, q.end.y)])
		p.material = solid  # opaque, so the visor reads as the emitter colour, not a white-out
		_eye_root.add_child(p)
		_eyes.append(p)
	_halo = Sprite2D.new()
	_halo.texture = HALO
	_halo.scale = Vector2(0.47, 0.47)
	_halo.position = Vector2(-0.5, 16.5)
	_halo.material = add
	_eye_root.add_child(_halo)
	_light = PointLight2D.new()
	_light.texture = LIGHT_TEX
	_light.texture_scale = 0.6
	_light.position = _halo.position
	_light.range_item_cull_mask = LightingRig.MASK_WORLD
	_eye_root.add_child(_light)
	_apply(0.0, FXPalette.LASER)


func _emitter_color() -> Color:
	var aug := _cat.get_node_or_null("Sprite/Augments") as CatAugments
	return aug.emitter_color() if aug else FXPalette.INDICATOR


func _physics_process(delta: float) -> void:
	_t += delta
	if _cat == null:
		_cat = get_tree().get_first_node_in_group("player") as Cat
		return
	var near := GameState.intelligence and not _cat.dead and absf(_cat.global_position.x - global_position.x) < react_range \
		and absf(_cat.global_position.y - global_position.y) < 120.0
	if near and not has_reacted:
		has_reacted = true
		_flicker = 0.9
		Sfx.play(self, "robot_chirp")
		reacted.emit()
	if near:
		_flicker = maxf(_flicker - delta, 0.0)
		wake = move_toward(wake, 1.0, delta * 2.5)
		if face_cat:
			_body.flip_h = _cat.global_position.x < global_position.x
			_eye_root.scale.x = -1.0 if _body.flip_h else 1.0
	else:
		wake = move_toward(wake, 0.0, delta * 0.8)
	eye_color = FXPalette.LASER.lerp(_emitter_color(), clampf(wake * 1.4, 0.0, 1.0))
	var level := lerpf(0.12, 1.0, wake)
	if _flicker > 0.0:
		# The wake-up stutter: on, off, on, in the cat's colour.
		level *= 0.1 if fmod(_flicker * 14.0, 1.0) < 0.5 else 1.0
	elif not near and wake <= 0.0:
		level *= 0.8 + 0.2 * sin(_t * 1.7)
	_apply(level, eye_color)
	_body.self_modulate = ASLEEP.lerp(AWAKE, wake)


func _apply(level: float, c: Color) -> void:
	for p in _eyes:
		p.color = Color(c * (0.7 + 0.7 * level), 1.0) if level > 0.0 else Color(0, 0, 0, 0)
		p.modulate.a = clampf(level, 0.0, 1.0)
	_halo.modulate = Color(c * 0.9 * level, 1.0)
	_light.color = c
	_light.energy = 0.9 * level


func _draw() -> void:
	# The dock: a steel pad under the feet, two clamps, a cable to the wall box.
	draw_rect(Rect2(-29, -4, 58, 4), Color("141a2c"))
	draw_rect(Rect2(-28, -3, 56, 2), Color("354655"))
	draw_rect(Rect2(-28, -3, 56, 1), Color("536a74"))
	for sx in [-23.0, 19.0]:
		draw_rect(Rect2(sx, -8, 4, 5), Color("2a4658"))
		draw_rect(Rect2(sx + 1, -7, 2, 1), FXPalette.INDICATOR)
	draw_rect(Rect2(35, -31, 15, 31), Color("10121f"))
	draw_rect(Rect2(36, -30, 13, 29), Color("2a4658"))
	draw_rect(Rect2(38, -27, 9, 4), Color("141a2c"))
	draw_rect(Rect2(39, -26, 7, 2), FXPalette.INDICATOR)
	draw_polyline(PackedVector2Array([Vector2(35, -20), Vector2(20, -17), Vector2(13, -7), Vector2(12, -3)]), Color("141a2c"), 2.0)
