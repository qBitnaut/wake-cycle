class_name MasterGate
extends StaticBody2D
## The Master Gate: a huge security gate in a gatehouse that rolls up into its
## header when told to (`open_gate`), grinding, shaking the camera and spilling
## warm dawn light as it rises. Shut it blocks the whole opening, floor to
## lintel. Origin = the middle of the base. Not a puzzle by itself: the
## PerimeterFinale opens it.

signal opened

const LIGHT_TEX := preload("res://assets/fx/light_soft.png")
const INK := Color("10121f")

@export var width := 96.0
@export var height_tiles := 7
@export var open_time := 4.2

var is_open := false
var opening := false
## 0 shut .. 1 fully rolled up.
var lift := 0.0

var _shape := RectangleShape2D.new()
var _cs := CollisionShape2D.new()
var _spill: PointLight2D
var _tick := 0.0


func _ready() -> void:
	collision_layer = 1
	collision_mask = 0
	z_index = 1
	var h := height_tiles * 32.0
	_shape.size = Vector2(width, h)
	_cs.shape = _shape
	_cs.position = Vector2(0, -h / 2.0)
	add_child(_cs)
	_spill = PointLight2D.new()
	_spill.texture = LIGHT_TEX
	_spill.texture_scale = 5.0
	_spill.color = Color(1.0, 0.78, 0.55)
	_spill.energy = 0.0
	_spill.position = Vector2(width * 0.5 + 40.0, -h * 0.4)
	_spill.range_item_cull_mask = LightingRig.MASK_WORLD
	add_child(_spill)


func open_gate() -> void:
	if opening or is_open:
		return
	opening = true
	var tw := create_tween()
	tw.tween_property(self, "lift", 1.0, open_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(func():
		opening = false
		is_open = true
		opened.emit())


## Open at once (a reload after the gate had opened).
func set_open_instant() -> void:
	lift = 1.0
	is_open = true
	_update_shape()


func _update_shape() -> void:
	var h := height_tiles * 32.0 * (1.0 - lift)
	_shape.size.y = maxf(h, 0.01)
	_cs.position.y = -h / 2.0
	_cs.disabled = h < 2.0
	_spill.energy = 1.7 * lift
	queue_redraw()


func _physics_process(delta: float) -> void:
	_update_shape()
	if opening:
		_tick -= delta
		if _tick <= 0.0:
			_tick = 0.45
			Sfx.play(self, "door", -6.0, 0.55 + randf() * 0.15)
			ScreenShake.shake_at(self, 0.22, 0.5)
			Debris.burst(get_parent(), global_position + Vector2(randf_range(-40, 40), -height_tiles * 32.0 * (1.0 - lift)), Color("5b7280"), 4)


func _draw() -> void:
	var h := height_tiles * 32.0
	var w := width
	var top := -h
	var shown := h * (1.0 - lift)
	# Side rails and the header box the door rolls into.
	draw_rect(Rect2(-w / 2.0 - 6, top - 14, w + 12, 16), INK)
	draw_rect(Rect2(-w / 2.0 - 5, top - 13, w + 10, 14), Color("354655"))
	draw_rect(Rect2(-w / 2.0 - 5, top - 13, w + 10, 2), Color("536a74"))
	draw_rect(Rect2(-w / 2.0 - 6, top, 6, h), Color("1c2c3b"))
	draw_rect(Rect2(w / 2.0, top, 6, h), Color("1c2c3b"))
	if lift > 0.001:
		# The dawn behind the gate, in the part the door has left: warm and bright (HDR, so it blooms).
		draw_polygon(
			PackedVector2Array([Vector2(-w / 2.0, top), Vector2(w / 2.0, top), Vector2(w / 2.0, 0), Vector2(-w / 2.0, 0)]),
			PackedColorArray([Color(1.0, 0.62, 0.5), Color(1.0, 0.62, 0.5), Color(1.9, 1.5, 1.0), Color(1.9, 1.5, 1.0)]))
	if shown > 1.0:
		draw_rect(Rect2(-w / 2.0, top, w, shown), INK)
		var y := top
		var i := 0
		while y < top + shown:
			var sh := minf(14.0, top + shown - y)
			var c := Color("2a4658") if i % 2 == 0 else Color("22384a")
			draw_rect(Rect2(-w / 2.0 + 2, y + 1, w - 4, maxf(sh - 2.0, 1.0)), c)
			draw_rect(Rect2(-w / 2.0 + 2, y + 1, w - 4, 1), Color("3d5866"))
			for rx in [-w / 2.0 + 6, w / 2.0 - 8]:
				draw_rect(Rect2(rx, y + 5, 2, 2), Color("0f1620"))
			y += 14.0
			i += 1
		# A centre seam, hazard stripes along the bottom edge, "MASTER GATE" plate.
		draw_rect(Rect2(-1, top, 2, shown), INK)
		var by := top + shown - 10.0
		var x := -w / 2.0
		var k := 0
		while x < w / 2.0:
			draw_rect(Rect2(x, by, 8, 10), Color("d07a26") if k % 2 == 0 else INK)
			x += 8.0
			k += 1
		if shown > 100.0:
			var font := preload("res://assets/fonts/monogram.ttf")
			draw_rect(Rect2(-26, top + 28, 52, 34), INK)
			draw_rect(Rect2(-25, top + 29, 50, 32), Color("354655"))
			draw_rect(Rect2(-23, top + 31, 46, 28), INK)
			draw_string(font, Vector2(-23, top + 44), "MASTER", HORIZONTAL_ALIGNMENT_CENTER, 46.0, 16, Color(FXPalette.SODIUM, 0.95))
			draw_string(font, Vector2(-23, top + 57), "GATE", HORIZONTAL_ALIGNMENT_CENTER, 46.0, 16, Color(FXPalette.SODIUM, 0.95))
			# Chevron warning bands across the door.
			var cy := top + 90.0
			while cy < top + shown - 24.0:
				var xx := -w / 2.0 + 4.0
				while xx < w / 2.0 - 8.0:
					draw_line(Vector2(xx, cy + 8), Vector2(xx + 8, cy), Color("d07a26"), 2.0)
					xx += 10.0
				cy += 40.0
