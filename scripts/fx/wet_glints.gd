class_name WetGlints
extends Node2D
## After the rain, in the sun: wet things twinkle and drip.
##
## Glints: tiny four-point stars that flare and fade at random spots inside
## `areas` (world rects: puddles, leaves, fence tops, roof edges). Drips:
## beads that swell along `drip_lines` (eaves, gutters, rails, branches),
## fall, catch the light as they fall and splash where they land (ringing a
## Puddle under them). Everything is drawn here at 1 art px with HDR colours,
## so the 2D glow blooms the brightest pixels. Only what is near the view is
## simulated.
##
## Put the node at the world origin; areas and lines are in world px.
##
## retire(rect, fade) switches off what belongs to something that goes away
## (Home's facade as it dissolves): drip lines crossing `rect` and areas inside
## it spawn no more, and their drops, splashes and glints fade out.

## Where glints may flare (world rects).
@export var areas: Array[Rect2] = []
## Glints per second per 10 000 px^2 of area in view.
@export var glint_rate := 2.4
## Drip lines: Vector4(x0, x1, hang_y, land_y), world px.
@export var drip_lines: Array[Vector4] = []
## Drops per second per 100 px of line.
@export var drip_rate := 0.22
@export var glint_color := Color(2.1, 1.95, 1.55)
@export var drop_color := Color(0.82, 0.92, 1.0)
@export var drop_glint := Color(1.9, 1.85, 1.6)
@export var gravity := 900.0

## Puddles that ring when a drop lands in them (filled by the level).
var puddles: Array = []
var glints_spawned := 0
var drops_landed := 0

var _glints: Array = []     # [pos, age, life, size, area]
var _drops: Array = []      # [pos, vy, state (0 swell, 1 fall), t, land_y, glint phase, line]
var _splashes: Array = []   # [pos, vel, age, line]
var _acc_g := 0.0
var _acc_d: Array = []
# Per line and per area: 1 live; once retired it falls to 0 at _*_fade per s.
var _line_a := PackedFloat32Array()
var _line_fade := PackedFloat32Array()
var _area_a := PackedFloat32Array()
var _area_fade := PackedFloat32Array()


func _ready() -> void:
	var m := CanvasItemMaterial.new()
	m.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = m
	_fit()


## Keeps the per-line and per-area state as long as the lists (new ones live).
func _fit() -> void:
	while _acc_d.size() < drip_lines.size():
		_acc_d.append(randf())
	while _line_a.size() < drip_lines.size():
		_line_a.append(1.0)
		_line_fade.append(0.0)
	while _area_a.size() < areas.size():
		_area_a.append(1.0)
		_area_fade.append(0.0)


## Switch off the drip lines that cross `rect` and the glint areas inside it,
## and fade out over `fade` seconds the drops (hanging or falling), splashes
## and glints they made; then they are gone.
func retire(rect: Rect2, fade := 0.0) -> void:
	_fit()
	var rate := 1.0 / maxf(fade, 0.001)
	for i in drip_lines.size():
		var l: Vector4 = drip_lines[i]
		if Rect2(l.x, l.z, l.y - l.x, 1.0).intersects(rect):
			_line_fade[i] = rate
	for i in areas.size():
		if rect.encloses(areas[i]):
			_area_fade[i] = rate


## Drops, splashes and glints still drawn from retired lines and areas.
func retired_live() -> int:
	var n := 0
	for d in _drops:
		n += 1 if _line_fade[d[6]] > 0.0 else 0
	for sp in _splashes:
		n += 1 if _line_fade[sp[3]] > 0.0 else 0
	for g in _glints:
		n += 1 if _area_fade[g[4]] > 0.0 else 0
	return n


func _view() -> Rect2:
	var cam := get_viewport().get_camera_2d()
	var size := get_viewport_rect().size
	var c := cam.get_screen_center_position() if cam else size * 0.5
	return Rect2(c - size * 0.5, size).grow(48.0)


func _process(delta: float) -> void:
	_fit()
	var view := _view()
	_spawn_glints(delta, view)
	_spawn_drops(delta, view)
	_step(delta)
	_fade_retired(delta)
	queue_redraw()


func _fade_retired(delta: float) -> void:
	var gone := false
	for i in _line_a.size():
		if _line_fade[i] > 0.0 and _line_a[i] > 0.0:
			_line_a[i] = maxf(_line_a[i] - _line_fade[i] * delta, 0.0)
			gone = gone or _line_a[i] <= 0.0
	for i in _area_a.size():
		if _area_fade[i] > 0.0 and _area_a[i] > 0.0:
			_area_a[i] = maxf(_area_a[i] - _area_fade[i] * delta, 0.0)
			gone = gone or _area_a[i] <= 0.0
	if gone:
		_drops = _drops.filter(func(d): return _line_a[d[6]] > 0.0)
		_splashes = _splashes.filter(func(sp): return _line_a[sp[3]] > 0.0)
		_glints = _glints.filter(func(g): return _area_a[g[4]] > 0.0)


func _spawn_glints(delta: float, view: Rect2) -> void:
	var live: Array[Rect2] = []
	var live_i: Array[int] = []
	var total := 0.0
	for k in areas.size():
		if _area_fade[k] > 0.0:
			continue
		var v := areas[k].intersection(view)
		if v.has_area():
			live.append(v)
			live_i.append(k)
			total += v.get_area()
	if total <= 0.0:
		return
	_acc_g += delta * glint_rate * total / 10000.0
	while _acc_g >= 1.0:
		_acc_g -= 1.0
		var pick := randf() * total
		for k in live.size():
			var r := live[k]
			pick -= r.get_area()
			if pick <= 0.0:
				var p := Vector2(floorf(randf_range(r.position.x, r.end.x)), floorf(randf_range(r.position.y, r.end.y)))
				_glints.append([p, 0.0, randf_range(0.45, 0.8), 2 if randf() < 0.35 else 1, live_i[k]])
				glints_spawned += 1
				break


func _spawn_drops(delta: float, view: Rect2) -> void:
	for i in drip_lines.size():
		var l: Vector4 = drip_lines[i]
		if _line_fade[i] > 0.0 or l.y < view.position.x or l.x > view.end.x:
			continue
		_acc_d[i] += delta * drip_rate * (l.y - l.x) / 100.0
		while _acc_d[i] >= 1.0:
			_acc_d[i] -= 1.0
			var x := floorf(randf_range(l.x, l.y))
			_drops.append([Vector2(x, l.z), 0.0, 0, 0.0, l.w, randf(), i])


func _step(delta: float) -> void:
	var i := 0
	while i < _glints.size():
		_glints[i][1] += delta
		if _glints[i][1] >= _glints[i][2]:
			_glints.remove_at(i)
		else:
			i += 1
	i = 0
	while i < _drops.size():
		var d: Array = _drops[i]
		d[3] += delta
		if d[2] == 0:
			if d[3] >= 0.7:
				d[2] = 1
				d[3] = 0.0
		else:
			d[1] += gravity * delta
			d[0].y += d[1] * delta
			if d[0].y >= d[4]:
				_land(Vector2(d[0].x, d[4]), d[6])
				_drops.remove_at(i)
				continue
		i += 1
	i = 0
	while i < _splashes.size():
		var s: Array = _splashes[i]
		s[2] += delta
		s[1].y += gravity * 0.6 * delta
		s[0] += s[1] * delta
		if s[2] > 0.3:
			_splashes.remove_at(i)
		else:
			i += 1


func _land(p: Vector2, line: int) -> void:
	drops_landed += 1
	for k in 3:
		_splashes.append([p + Vector2(0, -1), Vector2(randf_range(-28.0, 28.0), randf_range(-70.0, -35.0)), 0.0, line])
	for pd in puddles:
		var pu := pd as Puddle
		if pu and is_instance_valid(pu):
			var r := Rect2(pu.global_position, pu.size)
			if p.x >= r.position.x and p.x <= r.end.x and absf(p.y - r.position.y) < 6.0:
				pu.ripple(p.x, 0.5)


func _draw() -> void:
	for g in _glints:
		var p: Vector2 = g[0]
		var k: float = sin(PI * g[1] / g[2]) * _area_a[g[4]]
		var arm := 0
		if k > 0.75:
			arm = g[3]
		elif k > 0.4:
			arm = 1
		var core := Color(glint_color.r, glint_color.g, glint_color.b, clampf(k * 1.4, 0.0, 1.0))
		draw_rect(Rect2(p, Vector2.ONE), core)
		if arm > 0:
			var dim := Color(glint_color * 0.7, clampf(k, 0.0, 1.0))
			for a in range(1, arm + 1):
				var c := dim if a == 1 else Color(dim, dim.a * 0.6)
				draw_rect(Rect2(p + Vector2(a, 0), Vector2.ONE), c)
				draw_rect(Rect2(p + Vector2(-a, 0), Vector2.ONE), c)
				draw_rect(Rect2(p + Vector2(0, a), Vector2.ONE), c)
				draw_rect(Rect2(p + Vector2(0, -a), Vector2.ONE), c)
	for d in _drops:
		var p: Vector2 = d[0]
		var la: float = _line_a[d[6]]
		if d[2] == 0:
			var h := 1.0 if d[3] < 0.4 else 2.0
			draw_rect(Rect2(p, Vector2(1, h)), Color(drop_color, la))
			if d[3] > 0.4:
				draw_rect(Rect2(p + Vector2(0, h - 1), Vector2.ONE), Color(drop_glint, la))
		else:
			var flick: bool = fmod(d[3] * 9.0 + d[5], 1.0) < 0.35
			draw_rect(Rect2(Vector2(p.x, floorf(p.y) - 2), Vector2(1, 3)), Color(drop_color, 0.85 * la))
			if flick:
				draw_rect(Rect2(Vector2(p.x, floorf(p.y)), Vector2.ONE), Color(drop_glint, la))
	for s in _splashes:
		var a: float = (1.0 - s[2] / 0.3) * _line_a[s[3]]
		draw_rect(Rect2(s[0].floor(), Vector2.ONE), Color(drop_color, a))
