class_name MapMarker
extends Node2D
## A level's spot on the world map: a small plate on the ground in front of
## its landmark. Available levels glow and breathe in the cat's gold; finished
## ones settle to a quiet cream plate with a gold star and, underneath, the
## collectibles found there (the C-A-T letters, gems x/y); locked ones are a
## dark plate with a padlock; hidden secrets draw nothing.
## WorldMap builds one per level from data/levels.json.

enum State { HIDDEN, LOCKED, OPEN, DONE }

const ART := "res://assets/art_hd/map/"
const HALO := preload("res://assets/fx/halo.png")
const FONT := preload("res://assets/fonts/monogram.ttf")
const GOLD := Color(1.0, 0.82, 0.25)
const GOLD_HDR := Color(1.7, 1.25, 0.45)
const DIM := Color(0.36, 0.38, 0.48)
const CREAM := Color(0.93, 0.89, 0.80)

var id := ""
var state := State.LOCKED
var bonus := false
## Collectibles row: [found letters, letters there, gems found, gems there].
var letters_here: Array = []
var letters_found: Array = []
var gems_found := 0
var gems_total := 0
## Shows the collectibles row under a finished plate.
var show_pips := true

var _plates := {}
var _padlock: Texture2D
var _star: Texture2D
var _gem: Texture2D
var _halo: Sprite2D
var _t := randf() * 4.0
var _flash := 0.0
var _pop := 1.0
var _nope := 0.0


func _ready() -> void:
	for k in ["plate_open", "plate_done", "plate_locked"]:
		_plates[k] = load(ART + k + ".png")
	_padlock = load(ART + "padlock.png")
	_star = load(ART + "star.png")
	_gem = load(ART + "gem.png")
	_halo = Sprite2D.new()
	_halo.name = "Halo"
	_halo.texture = HALO
	_halo.position = Vector2(0, -2)
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_halo.material = add
	_halo.show_behind_parent = true
	add_child(_halo)
	_apply()


func set_state(s: State) -> void:
	state = s
	_apply()


## The plate lights up (a fresh level): a flash and a pop.
func light_up() -> void:
	set_state(State.OPEN)
	_flash = 1.0
	_pop = 1.6


## The level was just finished: the plate settles to DONE with a flash.
func stamp() -> void:
	set_state(State.DONE)
	_flash = 0.8
	_pop = 1.4


## A refused entry (a locked level): a short shake of the padlock.
func nope() -> void:
	_nope = 0.4


## A strong flare as the cat goes in.
func flare() -> void:
	_flash = 1.4


func _apply() -> void:
	visible = state != State.HIDDEN
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	_flash = maxf(_flash - delta * 1.6, 0.0)
	_pop = move_toward(_pop, 1.0, delta * 2.5)
	_nope = maxf(_nope - delta, 0.0)
	var breathe := 0.5 + 0.5 * sin(_t * 2.6)
	match state:
		State.OPEN:
			_halo.visible = true
			_halo.scale = Vector2(0.62, 0.30) * (1.0 + breathe * 0.12) * _pop
			_halo.modulate = Color(GOLD_HDR * (0.55 + breathe * 0.35 + _flash), 1.0)
		State.DONE:
			_halo.visible = _flash > 0.0
			_halo.scale = Vector2(0.62, 0.30) * _pop
			_halo.modulate = Color(Color(1.4, 1.3, 1.1) * _flash, 1.0)
		_:
			_halo.visible = false
	if state == State.OPEN or _flash > 0.0 or _nope > 0.0:
		queue_redraw()


func _draw() -> void:
	match state:
		State.OPEN:
			var k := 1.0 + _flash * 0.6
			_plate("plate_open", Color(k, k, k))
			if bonus:
				_icon(_star, Vector2(0, -12 - sin(_t * 2.6) * 1.5), Color(1, 1, 1))
		State.DONE:
			_plate("plate_done", Color(1, 1, 1))
			_icon(_star, Vector2(0, -12), Color(1.0, 1.0, 1.0))
			if show_pips:
				_draw_pips()
		State.LOCKED:
			_plate("plate_locked", Color(1, 1, 1))
			var shake := roundf(sin(_nope * 60.0) * 2.0) if _nope > 0.0 else 0.0
			_icon(_padlock, Vector2(shake, -10), Color(0.85, 0.87, 0.95))


func _plate(name: String, mod: Color) -> void:
	var tex: Texture2D = _plates[name]
	var sz := tex.get_size()
	draw_texture(tex, (-sz * 0.5).round() + Vector2(0, 1), mod)


func _icon(tex: Texture2D, at: Vector2, mod: Color) -> void:
	var sz := tex.get_size()
	draw_texture(tex, (at - sz * 0.5).round(), mod)


## C A T (gold when found, dim when not) and the gem count, on a dark slip
## under the plate. Levels with nothing to find show no row.
func _draw_pips() -> void:
	if letters_here.is_empty() and gems_total <= 0:
		return
	var parts: Array = []  # [text or texture, colour]
	for l in letters_here:
		parts.append([String(l), GOLD if letters_found.has(l) else DIM])
	if gems_total > 0:
		parts.append([_gem, Color(1, 1, 1) if gems_found > 0 else DIM])
		parts.append(["%d/%d" % [gems_found, gems_total], CREAM if gems_found < gems_total else GOLD])
	var w := 0.0
	var widths: Array = []
	for p in parts:
		var pw: float = (p[0] as Texture2D).get_width() + 1.0 if p[0] is Texture2D else FONT.get_string_size(p[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
		widths.append(pw)
		w += pw + 3.0
	w -= 3.0
	var x := roundf(-w * 0.5)
	var y := 9.0
	draw_rect(Rect2(x - 3, y - 1, w + 6, 11), Color(0.02, 0.03, 0.07, 0.72))
	for i in parts.size():
		var p: Array = parts[i]
		if p[0] is Texture2D:
			draw_texture(p[0], Vector2(x, y + 1), p[1])
		else:
			draw_string(FONT, Vector2(x, y + 8), p[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, p[1])
		x += widths[i] + 3.0
