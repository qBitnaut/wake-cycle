class_name GooTendrils
extends Node2D
## Goo tendrils rising out of a pool surface and leaning in to wrap whatever
## stands there. Drawn in whole pixels: lit ink bodies with a cool sheen on
## one edge, and emissive nanite tips on an unshaded child that bloom.
##
## The origin is a point on the pool surface. Set `amount` (0..1) and the
## tendrils ease toward it: up as the goo grips, back down as it lets go.
## GooPool.grip() makes two of these (behind and in front of the actor).

@export_range(1, 12) var count := 4
## Half-width of the root zone, px.
@export var spread := 12.0
@export var max_height := 18.0
## Offsets the pseudo-random shapes, so two sets never match.
@export var seed_offset := 0.0
@export var body_color := Color(0.045, 0.05, 0.085)
@export var sheen_color := Color(0.62, 0.72, 0.95)
@export var tip_a: Color = FXPalette.NANO_BLUE
@export var tip_b: Color = FXPalette.NANO_GREEN
## Seconds to rise to full height; falling back is a little quicker.
@export var rise_time := 1.4

var amount := 0.0
var _cur := 0.0
var _t := 0.0
var _tips: Node2D
var _tip_pts: Array[Vector3] = []


func _ready() -> void:
	_tips = Node2D.new()
	_tips.name = "Tips"
	var um := CanvasItemMaterial.new()
	um.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	_tips.material = um
	_tips.draw.connect(_draw_tips)
	add_child(_tips)


func _process(delta: float) -> void:
	_t += delta
	var rate := 1.0 / maxf(rise_time, 0.05)
	_cur = move_toward(_cur, amount, delta * (rate if amount > _cur else rate * 1.4))
	visible = _cur > 0.001
	if visible:
		queue_redraw()
		_tips.queue_redraw()


func _hash(v: float) -> float:
	return fposmod(sin(v * 12.9898 + seed_offset * 78.233) * 43758.5453, 1.0)


func _draw() -> void:
	_tip_pts.clear()
	var e := _cur * _cur * (3.0 - 2.0 * _cur)
	for i in count:
		var h1 := _hash(i + 1.0)
		var h2 := _hash(i + 17.0)
		var grow := clampf((e - h1 * 0.3) / 0.7, 0.0, 1.0)
		var height := floorf(max_height * (0.55 + 0.45 * h2) * grow)
		if height < 1.0:
			continue
		var t01 := (i + 0.5) / count
		var root := lerpf(-spread, spread, t01) + (h1 - 0.5) * 4.0
		var lean := -signf(root) * 3.0
		var x := root
		for y in int(height):
			var k := float(y) / height
			x = root + lean * k + sin(_t * 1.8 + h1 * 6.0 + y * 0.32) * 2.2 * pow(k, 1.2)
			var w := 3 if y < 2 else (2 if k < 0.65 else 1)
			var px := roundf(x - w * 0.5)
			draw_rect(Rect2(px, -y - 1, w, 1), body_color)
			if w > 1:
				draw_rect(Rect2(px, -y - 1, 1, 1), body_color.lerp(sheen_color, 0.25))
		_tip_pts.append(Vector3(roundf(x - 0.5), -height, h2))


func _draw_tips() -> void:
	for p in _tip_pts:
		var c := tip_a.lerp(tip_b, p.z)
		var pulse := 1.0 + 0.4 * sin(_t * 6.0 + p.z * 9.0)
		_tips.draw_rect(Rect2(p.x, p.y, 1, 1), Color(c.r * pulse * 1.3, c.g * pulse * 1.3, c.b * pulse * 1.3, 1.0))
