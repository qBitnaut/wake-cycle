class_name NanoHD
extends Node
## HD effects for the goo transformation, drawn at the display's native
## resolution over the CineZoom close-up (smooth, soft and bloomed on top of
## the pixel art):
##
##   veins      smooth glowing vein lines crawling up the cat along its baked
##              vein tree (assets/fx/cat_nano/veins.json), three soft layers
##              (halo, glow, hot core) with packets of light running up them
##   sparkles   motes shed by the racing vein heads and the lit veins
##   front      wet specular glints sliding along the rising goo front
##   eye flare  a bloom and an anamorphic streak on the eye
##   pulse()    the energy pulse at the absorb: rings, flash, sparkle burst
##   pop()      a small flash where an augment piece lands
##   mind       the awakened mind: a soft halo round the head, an eye glint
##
## Drive the properties from a sequence (TransformSequence does). Everything
## attached to the cat is clipped above `clip_world_y` (the goo surface the
## cat stands in), so nothing glows through the liquid. Needs an active
## CineZoom pass (zoom > 1 or letterbox on); without one it draws nothing.

const VEINS := "res://assets/fx/cat_nano/veins.json"
const MAX_SPARKS := 220
## Every size and speed here was tuned on the cat at 2x its 1x art; the cat is
## CatFrames.SCALE x now and the close-up zooms in to match, so they are all
## scaled by this to keep the same look on screen.
const K := CatFrames.SCALE / 2.0

var cine: CineZoom
var sprite: AnimatedSprite2D
## World y of the liquid surface the cat stands in (INF = no clip).
var clip_world_y := INF

var vein_progress := 0.0
## Multiplies the veins (fades them during the absorb).
var vein_fade := 1.0
var flash := 0.0
var eye := 0.0
## Goo front height in the frame's 0..1 bounds (< 0 hides the glints).
var front := -1.0
var mind := 0.0
var vein_color: Color = FXPalette.NANO_BLUE
var vein_color_alt: Color = FXPalette.NANO_GREEN
var eye_color: Color = FXPalette.NANO_GREEN
var mind_color := Color(0.75, 0.92, 1.0)

static var _data := {}
static var _dot: ImageTexture
static var _line: ImageTexture
static var _star: ImageTexture

var _item := RID()
var _t := 0.0
var _sparks: Array = []     # [game pos, game vel, age, life, size, color, seed]
var _rings: Array = []      # [game pos, age, strength, radius px, color, life s]
var _pops: Array = []       # [game pos, age, color]
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_priority = 1001  # after CineZoom has placed the view
	_rng.randomize()
	_make_textures()
	if _data.is_empty():
		_data = load_json(VEINS)


## The energy pulse: rings out from the cat, a flash and a sparkle burst.
func pulse(strength := 1.0) -> void:
	var c := _cat_centre()
	var col := vein_color.lerp(vein_color_alt, 0.5).lerp(Color.WHITE, 0.25)
	_rings.append([c, 0.0, strength, 70.0, col, 0.9])
	_rings.append([c, -0.12, strength * 0.6, 70.0, col, 0.9])
	for i in int(70 * strength):
		var a := _rng.randf() * TAU
		var sp := _rng.randf_range(30.0, 110.0)
		_spark(c + Vector2.from_angle(a) * _rng.randf_range(2.0, 10.0) * K, Vector2.from_angle(a) * sp,
			_rng.randf_range(0.4, 0.9), _rng.randf_range(0.8, 1.6), vein_color.lerp(vein_color_alt, _rng.randf()))


## The awakened mind's pulse: one small, soft ring from the head.
func mind_pulse() -> void:
	var fr := _frame()
	if fr.is_empty() or fr["eye"] == null:
		return
	var head := _game(Vector2(fr["eye"][0], fr["eye"][1]))
	if fr["ear"] != null:
		head = (head + _game(Vector2(fr["ear"][0] + 0.5, fr["ear"][1] + 0.5))) * 0.5
	_rings.append([head, 0.0, 0.55, 16.0, mind_color, 1.1])


## A small flash where an augment piece lands (`local` in sprite space).
func pop(local: Vector2, color: Color) -> void:
	if sprite == null:
		return
	var g := sprite.get_global_transform_with_canvas() * local
	_pops.append([g, 0.0, color])
	for i in 10:
		var a := _rng.randf() * TAU
		_spark(g, Vector2.from_angle(a) * _rng.randf_range(8.0, 26.0), _rng.randf_range(0.3, 0.6),
			_rng.randf_range(0.5, 1.0), color.lerp(Color.WHITE, 0.4))


func _process(delta: float) -> void:
	_t += delta
	_age(delta)
	if cine == null or not is_instance_valid(cine) or not cine.has_fx() or sprite == null:
		return
	if not _item.is_valid():
		_item = cine.fx_item()
		if not _item.is_valid():
			return
	var rs := RenderingServer
	rs.canvas_item_clear(_item)
	var wr := cine.window_rect()
	if clip_world_y < INF:
		var gy := (sprite.get_viewport().get_canvas_transform() * Vector2(0, clip_world_y)).y
		var cy := cine.game_to_window(Vector2(0, gy)).y
		cine.clip_fx(_item, Rect2(wr.position, Vector2(wr.size.x, maxf(cy - wr.position.y, 0.0))))
	var s := cine.window_scale() * K
	var fr := _frame()
	if not fr.is_empty():
		if vein_progress > 0.0 and vein_fade > 0.0:
			_draw_veins(fr, s, delta)
		if front >= 0.0:
			_draw_front(fr, s)
		if eye > 0.0 or mind > 0.0:
			_draw_eye(fr, s)
	_draw_rings(s)
	_draw_pops(s)
	_draw_sparks(s)


# ---- the cat's frame data ---------------------------------------------------------

func _frame() -> Dictionary:
	var sf := CatOverlay.sheet_frame(sprite)
	if sf.is_empty() or not _data.has("sheets") or not _data["sheets"].has(sf[0]):
		return {}
	var frames: Array = _data["sheets"][sf[0]]
	return frames[sf[1]] if sf[1] < frames.size() else {}


## Frame pixel (centre) -> game -> window.
func _win(fp: Vector2) -> Vector2:
	return cine.game_to_window(_game(fp))


func _game(fp: Vector2) -> Vector2:
	return sprite.get_global_transform_with_canvas() * CatOverlay.frame_to_local(sprite, fp)


func _cat_centre() -> Vector2:
	var fr := _frame()
	if fr.is_empty():
		return sprite.get_global_transform_with_canvas().origin
	var b: Array = fr["bbox"]
	return _game(Vector2((b[0] + b[2]) * 0.5 + 0.5, (b[1] + b[3]) * 0.5 + 0.5))


# ---- veins ----------------------------------------------------------------------

func _draw_veins(fr: Dictionary, s: float, delta: float) -> void:
	var p := vein_progress
	var heads: Array = []
	var lit: Array = []
	for ch in fr["c"]:
		var pts: Array = ch["p"]
		var arr: Array = ch["a"]
		var trunk: bool = ch["t"] == 1
		var run := PackedVector2Array()
		var runa := PackedFloat32Array()
		for i in pts.size():
			var a: float = arr[i]
			if a <= p:
				run.append(Vector2(pts[i][0] + 0.5, pts[i][1] + 0.5))
				runa.append(a)
				continue
			if i > 0 and float(arr[i - 1]) <= p:
				var k := (p - float(arr[i - 1])) / maxf(a - float(arr[i - 1]), 0.0001)
				var prev := Vector2(pts[i - 1][0] + 0.5, pts[i - 1][1] + 0.5)
				run.append(prev.lerp(Vector2(pts[i][0] + 0.5, pts[i][1] + 0.5), k))
				runa.append(p)
				heads.append(run[run.size() - 1])
			_vein_run(run, runa, trunk, s, lit)
			run = PackedVector2Array()
			runa = PackedFloat32Array()
		_vein_run(run, runa, trunk, s, lit)
	# Racing heads: hot points that shed sparks.
	var hc := Color(1.0, 1.0, 1.0)
	for h in heads:
		var w := _win(h)
		_dot_at(w, 2.2 * s, Color(hc, 0.85 * vein_fade))
		_dot_at(w, 5.0 * s, Color(vein_color.lerp(vein_color_alt, 0.5), 0.35 * vein_fade))
		if _rng.randf() < delta * 30.0:
			_spark(_game(h), Vector2(_rng.randf_range(-8, 8), _rng.randf_range(-16, -4)), _rng.randf_range(0.35, 0.8),
				_rng.randf_range(0.6, 1.2), vein_color_alt.lerp(Color.WHITE, 0.5))
	# Lit veins shed the odd mote too.
	if not lit.is_empty() and vein_fade > 0.2:
		for i in int(delta * 26.0 + _rng.randf()):
			var q: Vector2 = lit[_rng.randi() % lit.size()]
			_spark(_game(q), Vector2(_rng.randf_range(-5, 5), _rng.randf_range(-10, -2)), _rng.randf_range(0.4, 1.0),
				_rng.randf_range(0.4, 0.9), vein_color.lerp(vein_color_alt, _rng.randf()).lerp(Color.WHITE, 0.3))


func _vein_run(run: PackedVector2Array, runa: PackedFloat32Array, trunk: bool, s: float, lit: Array) -> void:
	if run.size() < 2:
		return
	for q in run:
		lit.append(q)
	var w := PackedVector2Array()
	for q in run:
		w.append(_win(q))
	var aa := runa
	w = _chaikin(w)
	aa = _chaikin_f(aa)
	w = _chaikin(w)
	aa = _chaikin_f(aa)
	var n := w.size()
	var halo := PackedColorArray()
	var glow := PackedColorArray()
	var core := PackedColorArray()
	for i in n:
		var a := aa[i]
		var hue := (0.72 if trunk else 0.12) + 0.2 * a
		var c := vein_color.lerp(vein_color_alt, clampf(hue, 0.0, 1.0))
		var packet := pow(0.5 + 0.5 * sin((a * 5.0 - _t * 1.6) * TAU), 6.0)
		var head := 1.0 - smoothstep(0.0, 0.06, vein_progress - a)
		var k := (0.75 + 0.6 * packet + 1.2 * flash + 0.8 * head) * vein_fade
		halo.append(Color(c, 0.24 * k))
		glow.append(Color(c, 0.5 * k))
		core.append(Color(c.lerp(Color.WHITE, 0.55 + 0.3 * head), minf(0.95 * k, 1.0)))
	_ribbon(w, (3.6 if trunk else 2.9) * s, halo)
	_ribbon(w, (1.35 if trunk else 1.05) * s, glow)
	_ribbon(w, maxf(1.8, (0.36 if trunk else 0.28) * s), core)


func _chaikin(pts: PackedVector2Array) -> PackedVector2Array:
	if pts.size() < 3:
		return pts
	var out := PackedVector2Array([pts[0]])
	for i in pts.size() - 1:
		out.append(pts[i].lerp(pts[i + 1], 0.25))
		out.append(pts[i].lerp(pts[i + 1], 0.75))
	out.append(pts[pts.size() - 1])
	return out


func _chaikin_f(v: PackedFloat32Array) -> PackedFloat32Array:
	if v.size() < 3:
		return v
	var out := PackedFloat32Array([v[0]])
	for i in v.size() - 1:
		out.append(lerpf(v[i], v[i + 1], 0.25))
		out.append(lerpf(v[i], v[i + 1], 0.75))
	out.append(v[v.size() - 1])
	return out


# ---- goo front, eye, mind ---------------------------------------------------------

func _draw_front(fr: Dictionary, s: float) -> void:
	var b: Array = fr["bbox"]
	var rows: Array = fr["rows"]
	var h := clampf(front * 1.2 - 0.1, 0.0, 1.0)
	if h <= 0.02 or h >= 0.98:
		return
	var y := roundf(b[3] - h * (b[3] - b[1]))
	var ri := int(y) - int(b[1])
	if ri < 0 or ri >= rows.size() or (rows[ri] as Array).is_empty():
		return
	var x0: float = rows[ri][0]
	var x1: float = rows[ri][1]
	var col := Color(0.8, 0.9, 1.0)
	for i in 5:
		var u := fposmod(i * 0.23 + _t * (0.1 + 0.03 * i), 1.0)
		var fade := sin(u * PI)
		var w := _win(Vector2(lerpf(x0 + 1.0, x1, u), y + 0.6))
		_stretched_dot(w, Vector2(3.2, 0.7) * s, Color(col, 0.65 * fade))
		_dot_at(w, 0.5 * s, Color(1, 1, 1, 0.7 * fade))


func _draw_eye(fr: Dictionary, s: float) -> void:
	if fr["eye"] == null:
		return
	var e := _win(Vector2(fr["eye"][0], fr["eye"][1]))
	var flick := 0.85 + 0.15 * sin(_t * 9.0)
	if eye > 0.0:
		var k := eye * flick
		_dot_at(e, 6.0 * s * (0.8 + 0.2 * k), Color(eye_color, 0.45 * k))
		_dot_at(e, 1.8 * s, Color(eye_color.lerp(Color.WHITE, 0.7), 0.9 * k))
		_stretched_dot(e, Vector2(16.0, 0.7) * s * (0.7 + 0.3 * k), Color(eye_color.lerp(Color.WHITE, 0.3), 0.55 * k))
		_stretched_dot(e, Vector2(0.6, 5.0) * s * k, Color(eye_color.lerp(Color.WHITE, 0.5), 0.3 * k))
	if mind > 0.0:
		var head := e
		if fr["ear"] != null:
			head = (e + _win(Vector2(fr["ear"][0] + 0.5, fr["ear"][1] + 0.5))) * 0.5
		var breathe := 0.85 + 0.15 * sin(_t * 3.0)
		_dot_at(head, 11.0 * s * breathe, Color(mind_color, 0.3 * mind))
		_dot_at(e, 1.6 * s, Color(mind_color, 0.55 * mind))
		_star_at(e, 3.2 * s * (0.7 + 0.3 * mind), Color(mind_color.lerp(Color.WHITE, 0.4), 0.55 * mind), _t * 0.6)


# ---- rings, pops, sparks -----------------------------------------------------------

func _age(delta: float) -> void:
	for r in _rings:
		r[1] += delta
	_rings = _rings.filter(func(r): return r[1] < r[5])
	for pp in _pops:
		pp[1] += delta
	_pops = _pops.filter(func(pp): return pp[1] < 0.6)
	for sp in _sparks:
		sp[2] += delta
		sp[0] += sp[1] * delta
		sp[1] = sp[1] * (1.0 - 1.6 * delta) + Vector2(0.0, -6.0 * K * delta)
	_sparks = _sparks.filter(func(sp): return sp[2] < sp[3])


func _spark(g: Vector2, v: Vector2, life: float, size: float, c: Color) -> void:
	if _sparks.size() >= MAX_SPARKS:
		_sparks.pop_front()
	_sparks.append([g, v * K, 0.0, life, size, c, _rng.randf() * 10.0])


func _draw_rings(s: float) -> void:
	for r in _rings:
		var t: float = r[1]
		if t < 0.0:
			continue
		var k: float = r[2]
		var life: float = r[5]
		var big: float = r[3]
		var c := cine.game_to_window(r[0])
		var rad := (big * 0.08 + big * (1.0 - pow(1.0 - minf(t / life, 1.0), 2.0))) * s
		var fade := (1.0 - t / life) * k
		var pts := PackedVector2Array()
		var cols := PackedColorArray()
		var col: Color = r[4]
		for i in 49:
			pts.append(c + Vector2.from_angle(i * TAU / 48.0) * Vector2(rad, rad * 0.62))
			cols.append(Color(col, 0.55 * fade))
		_ribbon(pts, (2.5 + 6.0 * t) * s * big / 70.0 + 1.5, cols)
		if t < 0.25:
			_dot_at(c, big * 0.43 * s, Color(col, 0.5 * (1.0 - t / 0.25) * k))


func _draw_pops(s: float) -> void:
	for pp in _pops:
		var t: float = pp[1]
		var w := cine.game_to_window(pp[0])
		var k := 1.0 - t / 0.6
		var c: Color = pp[2]
		_dot_at(w, 5.0 * s * (0.6 + t), Color(c, 0.6 * k))
		_star_at(w, 5.0 * s * (1.0 - 0.5 * t), Color(c.lerp(Color.WHITE, 0.5), 0.9 * k), t)


func _draw_sparks(s: float) -> void:
	for sp in _sparks:
		var t: float = sp[2] / sp[3]
		var w := cine.game_to_window(sp[0])
		var tw := 0.6 + 0.4 * sin(_t * 30.0 + sp[6])
		var a := sin(t * PI) * tw
		var size: float = sp[4] * s * 1.3
		var c: Color = sp[5]
		if size > 3.0:
			_star_at(w, size * 1.6, Color(c, 0.85 * a), sp[6])
		_dot_at(w, size * 0.9, Color(c, 0.7 * a))


# ---- primitives (RenderingServer, additive) ------------------------------------------

func _dot_at(p: Vector2, radius: float, c: Color) -> void:
	RenderingServer.canvas_item_add_texture_rect(_item, Rect2(p - Vector2(radius, radius), Vector2(radius, radius) * 2.0), _dot.get_rid(), false, c)


func _stretched_dot(p: Vector2, half: Vector2, c: Color) -> void:
	RenderingServer.canvas_item_add_texture_rect(_item, Rect2(p - half, half * 2.0), _dot.get_rid(), false, c)


func _star_at(p: Vector2, radius: float, c: Color, rot: float) -> void:
	var xf := Transform2D(rot, p)
	RenderingServer.canvas_item_add_set_transform(_item, xf)
	RenderingServer.canvas_item_add_texture_rect(_item, Rect2(-Vector2(radius, radius), Vector2(radius, radius) * 2.0), _star.get_rid(), false, c)
	RenderingServer.canvas_item_add_set_transform(_item, Transform2D.IDENTITY)


## A soft ribbon along `pts`: the line texture's gaussian across its width.
func _ribbon(pts: PackedVector2Array, width: float, cols: PackedColorArray) -> void:
	var n := pts.size()
	if n < 2:
		return
	var verts := PackedVector2Array()
	var uvs := PackedVector2Array()
	var vc := PackedColorArray()
	var idx := PackedInt32Array()
	for i in n:
		var t := (pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)])
		var nrm := Vector2(-t.y, t.x).normalized() * width * 0.5
		verts.append(pts[i] + nrm)
		verts.append(pts[i] - nrm)
		uvs.append(Vector2(0.5, 0.0))
		uvs.append(Vector2(0.5, 1.0))
		vc.append(cols[i])
		vc.append(cols[i])
		if i > 0:
			var b := (i - 1) * 2
			idx.append_array([b, b + 1, b + 2, b + 1, b + 3, b + 2])
	RenderingServer.canvas_item_add_triangle_array(_item, idx, verts, vc, uvs, PackedInt32Array(), PackedFloat32Array(), _line.get_rid())


static func _make_textures() -> void:
	if _dot != null:
		return
	var n := 64
	var dot := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var star := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var u := (x + 0.5) / n * 2.0 - 1.0
			var v := (y + 0.5) / n * 2.0 - 1.0
			var r2 := u * u + v * v
			var g := exp(-r2 * 4.5) * clampf(1.0 - r2, 0.0, 1.0)
			dot.set_pixel(x, y, Color(1, 1, 1, g))
			var arm := exp(-u * u * 220.0) * exp(-v * v * 3.0) + exp(-v * v * 220.0) * exp(-u * u * 3.0)
			var st := clampf(arm + exp(-r2 * 30.0), 0.0, 1.0) * clampf(1.0 - r2, 0.0, 1.0)
			star.set_pixel(x, y, Color(1, 1, 1, st))
	_dot = ImageTexture.create_from_image(dot)
	_star = ImageTexture.create_from_image(star)
	var line := Image.create(4, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		var v := (y + 0.5) / 32.0 * 2.0 - 1.0
		for x in 4:
			line.set_pixel(x, y, Color(1, 1, 1, exp(-v * v * 4.0) * (1.0 - v * v)))
	_line = ImageTexture.create_from_image(line)


static func load_json(path: String) -> Dictionary:
	var res = load(path)
	if res is JSON:
		return res.data
	var f := FileAccess.open(path, FileAccess.READ)
	if f:
		return JSON.parse_string(f.get_as_text())
	push_error("NanoHD: cannot read %s" % path)
	return {}
